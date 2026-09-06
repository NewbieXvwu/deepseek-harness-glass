import Darwin
import Foundation
import XCTest

@testable import GlassCore
@testable import GlassSpec

@MainActor
final class HarnessHostTransportSmokeTests: XCTestCase {
    func testVerifiedHostRemoteRecoversAndReopensSessionFollowAfterUnexpectedRestart() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let nodePath = environment["DSH_GLASS_HOST_NODE"],
              let entrypointPath = environment["DSH_GLASS_HOST_ENTRY"] else {
            throw XCTSkip("Host + Remote smoke test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-remote-smoke-\(UUID().uuidString)", isDirectory: true)
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
        XCTAssertFalse(
            initial.context.authenticatedHost.urlSession.configuration.httpCookieStorage === HTTPCookieStorage.shared,
            "authenticated Host must not use the process-global cookie jar"
        )
        let initialCookieStorage = try XCTUnwrap(
            initial.context.authenticatedHost.urlSession.configuration.httpCookieStorage
        )
        let initialSession = initial.context.authenticatedHost.urlSession
        let initialControllers = HarnessControllers(remote: initial.context.remote)
        let requestedID = "remote-smoke-\(UUID().uuidString.lowercased())"
        let created = try await initialControllers.sessions.create(.init(sessionId: requestedID))
        XCTAssertEqual(created.sessionId, requestedID)
        let initialSessions = try await initialControllers.sessions.list()
        XCTAssertTrue(initialSessions.items.contains { $0.sessionId == requestedID })

        let initialFollow = SessionRuntime(
            controller: initialControllers.sessions,
            generation: initial.context.events.generation,
            address: .session(sessionID: requestedID)
        )
        let initialSnapshot = try await initialFollow.open()
        XCTAssertEqual(initialSnapshot.address, .session(sessionID: requestedID))
        XCTAssertEqual(initialSnapshot.generation, initial.context.events.generation)
        let initialClientID = initial.context.events.ready.clientId
        await initialFollow.close()

        guard let initialPID = controller.ownedProcessIdentifier else {
            return XCTFail("ready Host must retain an owned process before unexpected termination")
        }
        XCTAssertEqual(kill(initialPID, SIGTERM), 0, "the smoke test must induce a real owned-Host termination")
        try await waitForTransition(controller, summary: "ready -> recovering", timeout: 8)

        let recovered = try await waitForReady(controller, excludingPID: initialPID, timeout: 15)
        XCTAssertNotEqual(recovered.endpoint, initial.endpoint, "port-zero restart must publish a fresh authenticated endpoint")
        XCTAssertNotEqual(recovered.context.events.ready.clientId, initialClientID, "restarted Host must bootstrap a fresh $events client identity")
        XCTAssertNotEqual(recovered.context.generation, initial.context.generation, "restarted Host must publish a fresh Remote authority generation")
        XCTAssertFalse(
            recovered.context.authenticatedHost.urlSession === initialSession,
            "restarted Host must receive a fresh authenticated URLSession"
        )
        let recoveredCookieStorage = try XCTUnwrap(
            recovered.context.authenticatedHost.urlSession.configuration.httpCookieStorage
        )
        XCTAssertFalse(
            recoveredCookieStorage === initialCookieStorage,
            "restarted Host must receive a fresh ephemeral cookie jar"
        )
        XCTAssertFalse(
            recoveredCookieStorage === HTTPCookieStorage.shared,
            "restarted Host must remain isolated from the process-global cookie jar"
        )
        let transitionSummaries = controller.stateTransitions.map(\.summary)
        XCTAssertTrue(transitionSummaries.contains("ready -> recovering"))
        XCTAssertTrue(transitionSummaries.contains("recovering -> starting"))
        XCTAssertTrue(transitionSummaries.contains("classifying -> ready"))

        let recoveredControllers = HarnessControllers(remote: recovered.context.remote)
        let recoveredSessions = try await recoveredControllers.sessions.list()
        XCTAssertTrue(
            recoveredSessions.items.contains { $0.sessionId == requestedID },
            "DSH_HOME-owned session must survive the Host process restart"
        )
        let recoveredFollow = SessionRuntime(
            controller: recoveredControllers.sessions,
            generation: recovered.context.events.generation,
            address: .session(sessionID: requestedID)
        )
        let recoveredSnapshot = try await recoveredFollow.open()
        XCTAssertEqual(recoveredSnapshot.address, .session(sessionID: requestedID))
        XCTAssertEqual(recoveredSnapshot.generation, recovered.context.events.generation)
        await recoveredFollow.close()
    }

    private func waitForTransition(
        _ controller: HarnessHostController,
        summary: String,
        timeout: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if controller.stateTransitions.map(\.summary).contains(summary) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Host did not record expected lifecycle transition: \(summary)")
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

    private enum SmokeError: Error { case timeout, hostFailed }

    private static let fixedCatalog = SupportedHostBuildCatalog(
        schemaVersion: 1,
        defaultBuildId: "dsh-0.1.2-rc.1-official-a66e470",
        builds: [SupportedHostBuildCatalog.Build(
            id: "dsh-0.1.2-rc.1-official-a66e470",
            officialSourceCommit: "a66e4702047846cdaa10c66c9d3df3951f5ea70d",
            dshPackageVersion: "0.1.2-rc.1",
            webFrontendPackageVersion: "0.1.2-rc.1",
            nodeRuntimeVersion: "24.19.0",
            minimumAppVersion: "0.4.0",
            minimumMacOS: "26.0",
            ciRunner: "macos-26",
            minimumXcodeMajor: 26,
            protocolFixtureRevision: "official-a66e470-remote-r1",
            uiSpecRevision: "official-a66e470-ui-spec-r1",
            supportedArchitectures: ["arm64"],
            verifiedAt: "2026-08-18",
            verificationState: "verified"
        )]
    )
}
