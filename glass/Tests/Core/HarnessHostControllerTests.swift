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
            XCTFail("T3.1 Host command-line test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
            return
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
            verifier: HostBuildVerifier(catalog: Self.fixedCatalog),
            startupTimeoutNanoseconds: 15_000_000_000
        )
        defer { controller.stop() }

        controller.start()
        let connection = try await waitForReady(controller, timeout: 15)
        XCTAssertEqual(connection.buildID, Self.fixedCatalog.defaultBuildId)
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


extension HarnessHostControllerTests {
    func testUnknownBuildBecomesUnverifiedAndDefaultsToWriteProtection() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let nodePath = environment["DSH_GLASS_HOST_NODE"],
              let entrypointPath = environment["DSH_GLASS_HOST_ENTRY"] else {
            XCTFail("T3.2 Host command-line test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
            return
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-unverified-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: URL(fileURLWithPath: nodePath),
            dshEntrypoint: URL(fileURLWithPath: entrypointPath),
            homeDirectory: root.appendingPathComponent("dsh", isDirectory: true),
            logFile: root.appendingPathComponent("logs/host.log")
        )
        let unknownCatalog = SupportedHostBuildCatalog(
            schemaVersion: 1,
            defaultBuildId: "unknown-dsh-build",
            builds: [SupportedHostBuildCatalog.Build(
                id: "unknown-dsh-build",
                officialSourceCommit: "99f6f02fecdb7dff40c3fbc9470f5907c29f74ca",
                dshPackageVersion: "0.0.0-unreviewed",
                webFrontendPackageVersion: "0.0.0-unreviewed",
                nodeRuntimeVersion: "24.19.0",
                minimumAppVersion: "0.4.0",
                minimumMacOS: "26.0",
                ciRunner: "macos-26",
                minimumXcodeMajor: 26,
                protocolFixtureRevision: "unknown",
                uiSpecRevision: "unknown",
                supportedArchitectures: ["arm64"],
                verifiedAt: nil,
                verificationState: "unverified"
            )]
        )
        let verifier = HostBuildVerifier(catalog: unknownCatalog)
        guard case let .unverified(reason) = verifier.verify(runtime: runtime) else {
            XCTFail("mismatched payload version must be unverified")
            return
        }
        XCTAssertTrue(reason.contains("version"))

        let controller = HarnessHostController(runtime: runtime, verifier: verifier)
        controller.start()
        guard case let .unverified(status) = controller.state else {
            XCTFail("unknown payload must enter explicit unverified state")
            return
        }
        XCTAssertFalse(status.developerWriteOverrideEnabled)
        XCTAssertNil(controller.ownedProcessIdentifier, "unverified build must not be launched as ready")

        let defaultPolicy = HostRPCAccessPolicy(trust: .unverified(reason: reason, developerWriteOverride: false))
        XCTAssertTrue(defaultPolicy.permits(method: "host.describe"))
        XCTAssertFalse(defaultPolicy.permits(method: "session.prompt"))
        XCTAssertFalse(defaultPolicy.trust.permitsWrites)

        let overridePolicy = HostRPCAccessPolicy(trust: .unverified(reason: reason, developerWriteOverride: true))
        XCTAssertTrue(overridePolicy.permits(method: "session.prompt"))
        XCTAssertTrue(overridePolicy.trust.permitsWrites)
    }
}
