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
            startupTimeoutNanoseconds: 30_000_000_000
        )
        defer { controller.stop() }

        controller.start()
        let connection = try await waitForReady(controller, timeout: 30)
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
        defaultBuildId: "dsh-0.1.0-rc.8-official-141eb6f",
        builds: [SupportedHostBuildCatalog.Build(
            id: "dsh-0.1.0-rc.8-official-141eb6f",
            officialSourceCommit: "141eb6fef83422698aef7a981029e843e8161534",
            dshPackageVersion: "0.1.0-rc.8",
            webFrontendPackageVersion: "0.1.0-rc.8",
            nodeRuntimeVersion: "24.19.0",
            minimumAppVersion: "0.4.0",
            minimumMacOS: "26.0",
            ciRunner: "macos-26",
            minimumXcodeMajor: 26,
            protocolFixtureRevision: "official-141eb6f-web-ui-r1",
            uiSpecRevision: "official-141eb6f-ui-spec-r1",
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
                officialSourceCommit: "141eb6fef83422698aef7a981029e843e8161534",
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


extension HarnessHostControllerTests {
    func testLifecycleTransitionsAreLoggedAndPresentationUsesOfficialLocale() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let nodePath = environment["DSH_GLASS_HOST_NODE"],
              let entrypointPath = environment["DSH_GLASS_HOST_ENTRY"] else {
            XCTFail("T3.3 Host command-line test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
            return
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
        let controller = HarnessHostController(runtime: runtime, verifier: HostBuildVerifier(catalog: Self.fixedCatalog))
        defer { controller.stop() }
        controller.start()
        _ = try await waitForReady(controller, timeout: 15)
        controller.stop()
        try await waitForIdle(controller, timeout: 8)

        let transitionSummaries = controller.stateTransitions.map(\.summary)
        XCTAssertTrue(transitionSummaries.contains("idle -> startingOwned"))
        XCTAssertTrue(transitionSummaries.contains("startingOwned -> verifying"))
        XCTAssertTrue(transitionSummaries.contains("verifying -> ready"))
        XCTAssertTrue(transitionSummaries.contains("ready -> stopping"))
        XCTAssertTrue(transitionSummaries.contains("stopping -> idle"))
        XCTAssertTrue(controller.recentLogLines.contains(where: { $0.contains("[host] transition") }))

        let probing = HostLifecyclePresentation.make(state: .probingExternal(URL(string: "http://127.0.0.1:43123")!))
        XCTAssertEqual(probing.title, OfficialUISpec.LocaleCatalog.value(namespace: "locale", key: "loading", language: "en"))
        XCTAssertFalse(probing.permitsInteraction)
        let failed = HostLifecyclePresentation.make(state: .failed(HostFailure(
            kind: .verificationFailed,
            message: "fixture failure",
            exitStatus: nil,
            logPath: runtime.logFile.path
        )))
        XCTAssertEqual(failed.title, OfficialUISpec.LocaleCatalog.value(namespace: "locale", key: "load.failed", language: "en"))
        XCTAssertEqual(failed.retryTitle, OfficialUISpec.LocaleCatalog.value(namespace: "locale", key: "retry", language: "en"))
    }
}


extension HarnessHostControllerTests {
    func testAnnouncementParserAcceptsBoundedSplitLoopbackEndpointAndRejectsMalformedInput() {
        let prefix = String(repeating: "x", count: 1_200)
        let output = prefix + "dsh web: http://127.0.0.1:43123/api\n"
        let endpoint = HarnessHostController.announcedEndpoint(in: output, fromUTF16Offset: 1_100)
        XCTAssertEqual(endpoint?.absoluteString, "http://127.0.0.1:43123/api")
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: https://127.0.0.1:43123", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: http://localhost:43123", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: "dsh web: http://127.0.0.1", fromUTF16Offset: 0))
        XCTAssertNil(HarnessHostController.announcedEndpoint(in: output, fromUTF16Offset: -1))
    }

    func testDiagnosticsAreCopyableCompleteAndRedacted() async throws {
        let recorder = HostDiagnosticRecorder(dshHome: "/tmp/diagnostic-home")
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:43123"))
        await recorder.recordVerified(build: Self.fixedCatalog.builds[0], endpoint: endpoint, pid: 4321)
        let sseTime = Date(timeIntervalSince1970: 1_700_000_000)
        await recorder.recordSSEActivity(at: sseTime)
        await recorder.recordRPCError(NSError(
            domain: "fixture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "api_key=top-secret cookie=session-cookie Authorization: Bearer bearer-secret https://user:password@example.test"]
        ))
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.hostBuildID, Self.fixedCatalog.defaultBuildId)
        XCTAssertEqual(snapshot.port, 43123)
        XCTAssertEqual(snapshot.dshHome, "/tmp/diagnostic-home")
        XCTAssertEqual(snapshot.ownedProcessID, 4321)
        XCTAssertEqual(snapshot.ownership, "owned")
        XCTAssertEqual(snapshot.lastSSEAt, sseTime)
        XCTAssertEqual(snapshot.protocolFixtureRevision, "official-141eb6f-web-ui-r1")
        XCTAssertEqual(snapshot.pluginCompatibility, "pinned-compatible")
        let copy = snapshot.copyableText()
        for required in ["hostBuild=", "port=", "dshHome=", "ownership=", "pid=", "lastSSEAt=", "lastRPCError=", "protocolFixtureRevision=", "pluginCompatibility=", "lifecycle="] {
            XCTAssertTrue(copy.contains(required), "diagnostic copy must include \(required)")
        }
        for secret in ["top-secret", "session-cookie", "bearer-secret", "user:password"] {
            XCTAssertFalse(copy.contains(secret), "diagnostic copy must redact \(secret)")
        }
        XCTAssertTrue(copy.contains("<redacted>"))
    }

    func testHostLogRedactorIsStableAcrossRepeatedCallsAndPreservesURLScheme() {
        let input = "Authorization: Bearer alpha-token cookie=browser-cookie https://user:password@example.test/path secret=hidden"
        let expected = HostLogRedactor.redact(input)
        XCTAssertEqual(HostLogRedactor.redact(input), expected)
        XCTAssertEqual(HostLogRedactor.redact(expected), expected)
        XCTAssertTrue(expected.contains("https://<redacted>@example.test/path"))
        for secret in ["alpha-token", "browser-cookie", "user:password", "hidden"] {
            XCTAssertFalse(expected.contains(secret), "redactor must remove \(secret)")
        }
    }
}


extension HarnessHostControllerTests {
    func testPlannedBuildFailsClosedAfterPayloadMetadataMatches() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-planned-build-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let node = root.appendingPathComponent("node")
        FileManager.default.createFile(atPath: node.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let entry = root.appendingPathComponent("payload/node_modules/@deepseek-ai/dsh/lib/cli.js")
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: entry.path, contents: Data())
        try Data("{\"version\":\"0.1.0-rc.8\"}".utf8).write(
            to: entry.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("package.json")
        )
        let webManifest = root.appendingPathComponent("payload/node_modules/@deepseek-ai/dsh-web-frontend/package.json")
        try FileManager.default.createDirectory(at: webManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"version\":\"0.1.0-rc.8\"}".utf8).write(to: webManifest)

        let build = SupportedHostBuildCatalog.Build(
            id: "planned-rc8",
            officialSourceCommit: "141eb6fef83422698aef7a981029e843e8161534",
            dshPackageVersion: "0.1.0-rc.8",
            webFrontendPackageVersion: "0.1.0-rc.8",
            nodeRuntimeVersion: "24.19.0",
            minimumAppVersion: "0.4.0",
            minimumMacOS: "26.0",
            ciRunner: "macos-26",
            minimumXcodeMajor: 26,
            protocolFixtureRevision: "official-141eb6f-web-ui-r1",
            uiSpecRevision: "official-141eb6f-ui-spec-r1",
            supportedArchitectures: ["arm64"],
            verifiedAt: nil,
            verificationState: "planned"
        )
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: node,
            dshEntrypoint: entry,
            homeDirectory: root.appendingPathComponent("dsh", isDirectory: true),
            logFile: root.appendingPathComponent("host.log")
        )
        let catalog = SupportedHostBuildCatalog(schemaVersion: 1, defaultBuildId: build.id, builds: [build])

        XCTAssertEqual(
            HostBuildVerifier(catalog: catalog).verify(runtime: runtime),
            .unverified(reason: "Bundled Host build is awaiting the required macOS CI verification.")
        )
    }
}
