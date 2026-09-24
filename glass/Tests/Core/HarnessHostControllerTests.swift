import Darwin
import Foundation
import XCTest

@testable import GlassCore
@testable import GlassSpec

@MainActor
final class HarnessHostControllerTests: XCTestCase {
    func testOwnedHostStartsReusesAndStopsWithoutLeavingProcess() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let nodePath = environment["DSH_GLASS_HOST_NODE"],
              let entrypointPath = environment["DSH_GLASS_HOST_ENTRY"] else {
            throw XCTSkip("Host command-line test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-host-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: URL(fileURLWithPath: nodePath),
            dshEntrypoint: URL(fileURLWithPath: entrypointPath),
            homeDirectory: root.appendingPathComponent("dsh", isDirectory: true),
            logFile: root.appendingPathComponent("logs/host.log")
        )
        let controller = HarnessHostController(
            runtime: runtime,
            startupTimeoutNanoseconds: 30_000_000_000
        )
        defer { controller.stop() }

        controller.start()
        let connection = try await waitForReady(controller, timeout: 30)
        XCTAssertEqual(connection.endpoint.scheme, "http")
        XCTAssertEqual(connection.endpoint.host, "127.0.0.1")
        XCTAssertNotNil(connection.endpoint.port)
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.homeDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.logFile.path))

        guard let firstPID = controller.ownedProcessIdentifier else {
            XCTFail("ready Host must retain an owned process")
            return
        }
        controller.start()
        XCTAssertEqual(controller.ownedProcessIdentifier, firstPID, "start() must reuse the owned ready Host")

        controller.stop()
        try await waitForIdle(controller, timeout: 8)
        XCTAssertNil(controller.ownedProcessIdentifier)
        XCTAssertEqual(kill(firstPID, 0), -1, "stopped Host PID must not remain alive")
        XCTAssertEqual(errno, ESRCH, "stopped Host PID must be absent rather than merely inaccessible")
    }

    func testLifecycleTransitionsFollowLaunchAuthenticationAndRemoteReadiness() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let nodePath = environment["DSH_GLASS_HOST_NODE"],
              let entrypointPath = environment["DSH_GLASS_HOST_ENTRY"] else {
            throw XCTSkip("Host command-line test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-transition-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: URL(fileURLWithPath: nodePath),
            dshEntrypoint: URL(fileURLWithPath: entrypointPath),
            homeDirectory: root.appendingPathComponent("dsh", isDirectory: true),
            logFile: root.appendingPathComponent("logs/host.log")
        )
        let controller = HarnessHostController(runtime: runtime)
        defer { controller.stop() }
        controller.start()
        _ = try await waitForReady(controller, timeout: 15)
        controller.stop()
        try await waitForIdle(controller, timeout: 8)

        XCTAssertEqual(
            controller.stateTransitions.map(\.summary),
            ["idle -> starting", "starting -> authenticating", "authenticating -> connecting", "connecting -> ready", "ready -> stopping", "stopping -> idle"]
        )
        XCTAssertTrue(controller.recentLogLines.contains(where: { $0.contains("[host] transition") }))

        let failed = HostLifecyclePresentation.make(state: .failed(HostFailure(
            kind: .verificationFailed,
            message: "fixture failure",
            exitStatus: nil,
            logPath: runtime.logFile.path
        )))
        XCTAssertEqual(failed.title, OfficialUISpec.LocaleCatalog.value(namespace: "locale", key: "load.failed", language: "en"))
        XCTAssertEqual(failed.retryTitle, OfficialUISpec.LocaleCatalog.value(namespace: "locale", key: "retry", language: "en"))
    }

    func testAnnouncementParserAcceptsBoundedSplitLoopbackEndpointAndRejectsMalformedInput() {
        let prefix = String(repeating: "x", count: 1_200)
        let output = prefix + "dsh web: http://127.0.0.1:43123/api\n"
        let endpoint = HarnessHostController.announcedEndpoint(in: output, fromUTF16Offset: 1_100)
        XCTAssertEqual(endpoint?.absoluteString, "http://127.0.0.1:43123/api")
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: https://127.0.0.1:43123", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: http://localhost:43123", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: http://127.0.0.1", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: http://fixture-user@127.0.0.1:43123", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: http://127.0.0.1:0", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: output, fromUTF16Offset: -1))
    }

    func testDiagnosticsReportRuntimeFactsAndRedactSecrets() async throws {
        let recorder = HostDiagnosticRecorder(dshHome: "/tmp/diagnostic-home")
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:43123"))
        await recorder.recordConnected(endpoint: endpoint, pid: 4321, generation: .init(rawValue: 7))
        await recorder.recordRPCError(NSError(
            domain: "fixture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "api_key=top-secret cookie=session-cookie Authorization: Bearer bearer-secret {\"api_key\":\"json-secret\\\"escaped\",\"token\":\"json-token\"}"]
        ))
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.port, 43123)
        XCTAssertEqual(snapshot.dshHome, "/tmp/diagnostic-home")
        XCTAssertEqual(snapshot.ownedProcessID, 4321)
        XCTAssertEqual(snapshot.ownership, "owned")
        XCTAssertEqual(snapshot.remoteGeneration, 7)
        XCTAssertEqual(snapshot.streamState, "ready")
        let copy = snapshot.copyableText()
        for secret in ["top-secret", "session-cookie", "bearer-secret", "json-secret", "json-token"] {
            XCTAssertFalse(copy.contains(secret), "diagnostic copy must redact \(secret)")
        }
        XCTAssertTrue(copy.contains("<redacted>"))
    }

    func testHostLogRedactorMasksCredentialValuesAndIsIdempotent() {
        let input = "Authorization: Bearer alpha-token cookie=browser-cookie secret=hidden {\"api_key\":\"json-secret\\\"escaped\",\"password\":\"json-password\"} plain"
        let redacted = HostLogRedactor.redact(input)
        for secret in ["alpha-token", "browser-cookie", "hidden", "json-secret", "json-password"] {
            XCTAssertFalse(redacted.contains(secret), "redactor must remove \(secret)")
        }
        XCTAssertTrue(redacted.contains("Bearer <redacted>"))
        XCTAssertTrue(redacted.contains("cookie=<redacted>"))
        XCTAssertTrue(redacted.contains("\"api_key\":\"<redacted>\""))
        XCTAssertTrue(redacted.contains("\"password\":\"<redacted>\""))
        XCTAssertTrue(redacted.hasSuffix(" plain"))
        XCTAssertEqual(HostLogRedactor.redact(redacted), redacted)
        XCTAssertEqual(HostLogRedactor.redact("no credentials here"), "no credentials here")
    }

    private func waitForReady(_ controller: HarnessHostController, timeout: TimeInterval) async throws -> HostConnection {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case let .ready(connection) = controller.state { return connection }
            if case let .failed(failure) = controller.state {
                XCTFail("Host unexpectedly failed: \(failure.message); log=\(failure.logPath)")
                throw HostTestError.failed
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Host did not reach ready; state=\(String(describing: controller.state))")
        throw HostTestError.timeout
    }

    private func waitForIdle(_ controller: HarnessHostController, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .idle = controller.state { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Host did not stop; state=\(String(describing: controller.state))")
        throw HostTestError.timeout
    }

    private enum HostTestError: Error { case failed, timeout }
}
