import Darwin
import Foundation
import XCTest

@testable import GlassCore
@testable import GlassSpec

@MainActor
final class HarnessHostTransportSmokeTests: XCTestCase {
    func testVerifiedHostTransportSmokeRecoversAndResubscribesAfterUnexpectedRestart() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let nodePath = environment["DSH_GLASS_HOST_NODE"],
              let entrypointPath = environment["DSH_GLASS_HOST_ENTRY"] else {
            XCTFail("T3.6 Host + transport smoke test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-t36-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: URL(fileURLWithPath: nodePath),
            dshEntrypoint: URL(fileURLWithPath: entrypointPath),
            homeDirectory: root.appendingPathComponent("dsh", isDirectory: true),
            logFile: root.appendingPathComponent("logs/host.log")
        )
        let controller = HarnessHostController(
            runtime: runtime,
            verifier: HostBuildVerifier(catalog: Self.fixedCatalog),
            startupTimeoutNanoseconds: 15_000_000_000
        )
        defer { controller.stop() }

        controller.start()
        let initial = try await waitForReady(controller, excludingPID: nil, timeout: 15)
        XCTAssertEqual(initial.buildID, Self.fixedCatalog.defaultBuildId)

        let initialAPIs = verifiedAPIs(for: initial)
        _ = try await initialAPIs.host.describe()
        let created = try await initialAPIs.sessions.create()
        let initialSessions = try await initialAPIs.sessions.list()
        XCTAssertTrue(
            initialSessions.items.contains { $0.sessionId == created.sessionId },
            "session.create must become observable through the official session.list facade"
        )

        let firstSubscriber = SSEClient(baseURL: initial.endpoint)
        let firstSubscribed = try await awaitSubscription(
            from: firstSubscriber,
            sessionID: created.sessionId,
            timeout: 8
        )
        XCTAssertEqual(firstSubscribed.method, "session/subscribed")
        await initial.diagnostics.recordSSEActivity()

        guard let initialPID = controller.ownedProcessIdentifier else {
            XCTFail("ready Host must retain an owned process before unexpected termination")
            return
        }
        XCTAssertEqual(kill(initialPID, SIGTERM), 0, "the smoke test must induce a real owned-Host termination")

        try await waitForReconnectTrace(from: firstSubscriber, timeout: 8)
        let networkError = await captureTransportError {
            _ = try await initialAPIs.host.describe()
        }
        guard case .network = networkError else {
            return XCTFail("old endpoint after Host termination must surface network state, got \(networkError)")
        }
        XCTAssertEqual(networkError.disposition, .retryable)
        let networkDiagnostics = await initial.diagnostics.snapshot()
        XCTAssertEqual(networkDiagnostics.lifecycle, "recovering")
        XCTAssertNotNil(networkDiagnostics.lastRPCError, "network transport failure must be retained in copyable diagnostics")
        XCTAssertTrue(networkDiagnostics.copyableText().contains("lastRPCError="))

        let recovered = try await waitForReady(controller, excludingPID: initialPID, timeout: 15)
        XCTAssertNotEqual(recovered.endpoint, initial.endpoint, "port-zero restart must publish a fresh verified endpoint")
        let transitionSummaries = controller.stateTransitions.map(\.summary)
        XCTAssertTrue(transitionSummaries.contains("ready -> recovering"), "unexpected Host termination must enter explicit recovering state")
        XCTAssertTrue(transitionSummaries.contains("recovering -> startingOwned"), "recovery must restart the owned Host")
        XCTAssertTrue(transitionSummaries.contains("verifying -> ready"), "recovered Host must repeat host.describe verification")

        let recoveredAPIs = verifiedAPIs(for: recovered)
        let recoveredSessions = try await recoveredAPIs.sessions.list()
        XCTAssertTrue(
            recoveredSessions.items.contains { $0.sessionId == created.sessionId },
            "DSH_HOME-owned session must survive the Host process restart"
        )
        let recoveredSubscriber = SSEClient(baseURL: recovered.endpoint)
        let recoveredSubscribed = try await awaitSubscription(
            from: recoveredSubscriber,
            sessionID: created.sessionId,
            timeout: 8
        )
        XCTAssertEqual(recoveredSubscribed.method, "session/subscribed")
        await recovered.diagnostics.recordSSEActivity()

        let diagnostics = await recovered.diagnostics.snapshot()
        XCTAssertEqual(diagnostics.hostBuildID, Self.fixedCatalog.defaultBuildId)
        XCTAssertNotNil(diagnostics.lastSSEAt, "real mux subscription must update diagnostics through the smoke consumer")
    }

    func testTransport503MapsToRetryableStateWithoutEscapingProcess() async throws {
        let responseSession = makeFiveHundredSession()
        let transport = DSHClientTransport(
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:9911")),
            accessPolicy: HostRPCAccessPolicy(trust: .verified(Self.fixedCatalog.builds[0])),
            session: responseSession
        )

        let error = await captureTransportError {
            _ = try await transport.call(method: "host.describe", payload: .object([:]))
        }
        guard case let .invalidHTTPStatus(status, _) = error else {
            return XCTFail("HTTP 503 must retain explicit carrier status, got \(error)")
        }
        XCTAssertEqual(status, 503)
        XCTAssertEqual(error.disposition, .retryable)
    }

    private func verifiedAPIs(for connection: HostConnection) -> HarnessAPIs {
        HarnessAPIs(
            baseURL: connection.endpoint,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(connection.build)),
            diagnostics: connection.diagnostics
        )
    }

    private func awaitSubscription(
        from client: SSEClient,
        sessionID: String,
        timeout: TimeInterval
    ) async throws -> RPCServerRequest {
        let collector = Task { () throws -> RPCServerRequest in
            let stream = await client.reconnectingStream(
                .mux,
                policy: SSEReconnectPolicy(initialDelay: 0.05, maximumDelay: 0.1, multiplier: 1)
            )
            for try await frame in stream {
                guard frame.method == "session/subscribed",
                      frame.payload.objectValue?["sessionId"]?.stringValue == sessionID else {
                    continue
                }
                return frame
            }
            throw SmokeError.streamEnded
        }
        defer { collector.cancel() }
        return try await value(of: collector, timeout: timeout)
    }

    private func waitForReconnectTrace(from client: SSEClient, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let traces = await client.recentReconnectTraces()
            if traces.contains(where: { $0.outcome == .reconnecting }) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("SSE/WebSocket stream did not expose a reconnecting trace after Host termination")
        throw SmokeError.timeout
    }

    private func waitForReady(
        _ controller: HarnessHostController,
        excludingPID: Int32?,
        timeout: TimeInterval
    ) async throws -> HostConnection {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case let .ready(connection) = controller.state,
               excludingPID == nil || controller.ownedProcessIdentifier != excludingPID {
                return connection
            }
            if case let .failed(failure) = controller.state {
                XCTFail("Host unexpectedly failed: \(failure.message); log=\(failure.logPath)")
                throw SmokeError.hostFailed
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Host did not reach expected ready state; state=\(String(describing: controller.state))")
        throw SmokeError.timeout
    }

    private func value<T: Sendable>(of task: Task<T, Error>, timeout: TimeInterval) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await task.value }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw SmokeError.timeout
            }
            guard let first = try await group.next() else { throw SmokeError.timeout }
            group.cancelAll()
            return first
        }
    }

    private func captureTransportError(_ operation: () async throws -> Void) async -> DSHTransportError {
        do {
            try await operation()
            XCTFail("operation unexpectedly succeeded")
            return .decoding("smoke operation unexpectedly succeeded")
        } catch let error as DSHTransportError {
            return error
        } catch {
            XCTFail("operation escaped DSHTransportError taxonomy: \(error)")
            return .decoding(String(describing: error))
        }
    }

    private func makeFiveHundredSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmokeFiveHundredURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private enum SmokeError: Error { case streamEnded, timeout, hostFailed }

    private static let fixedCatalog = SupportedHostBuildCatalog(
        schemaVersion: 1,
        defaultBuildId: "dsh-0.1.0-rc.7-official-99f6f02",
        builds: [SupportedHostBuildCatalog.Build(
            id: "dsh-0.1.0-rc.7-official-99f6f02",
            officialSourceCommit: "99f6f02fecdb7dff40c3fbc9470f5907c29f74ca",
            dshPackageVersion: "0.1.0-rc.7",
            webFrontendPackageVersion: "0.1.0-rc.7",
            nodeRuntimeVersion: "24.19.0",
            minimumAppVersion: "0.4.0",
            minimumMacOS: "26.0",
            ciRunner: "macos-26",
            minimumXcodeMajor: 26,
            protocolFixtureRevision: "official-99f6f02-web-ui-r1",
            uiSpecRevision: "official-99f6f02-ui-spec-r1",
            supportedArchitectures: ["arm64"],
            verifiedAt: "2026-08-18",
            verificationState: "verified"
        )]
    )
}

private final class SmokeFiveHundredURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 503,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("temporary Host outage".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
