import Foundation
import XCTest

@testable import GlassCore
@testable import GlassSpec

final class HostBuildPostHandshakeClassificationTests: XCTestCase {
    func testPreparationKeepsUnknownPackageFactsAsRunnableCandidate() throws {
        let fixture = try makeRuntime(dshVersion: "9.9.9-next", webVersion: "9.9.9-next")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let verifier = HostBuildVerifier(catalog: fixture.catalog)

        let preparation = verifier.prepare(runtime: fixture.runtime)
        guard case let .candidate(candidate) = preparation else {
            XCTFail("Unknown package facts must remain a runnable candidate until authenticated Remote readiness")
            return
        }
        XCTAssertEqual(candidate.dshVersion, "9.9.9-next")
        XCTAssertEqual(candidate.webFrontendVersion, "9.9.9-next")

        XCTAssertEqual(
            verifier.classify(candidate: candidate),
            .bestEffort(
                fixture.catalog.builds[0],
                reason: "Host package facts differ from the verified rc.1 catalog; attempting the rc.1 Remote contract best-effort."
            )
        )
    }

    func testPreparationRejectsCatalogThatCannotRepresentRc1Authority() throws {
        let fixture = try makeRuntime(dshVersion: "0.1.2-rc.1", webVersion: "0.1.2-rc.1", sourceCommit: "unrelated")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertEqual(
            HostBuildVerifier(catalog: fixture.catalog).prepare(runtime: fixture.runtime),
            .unsupported(reason: "Bundled Host catalog does not match the locked official source commit.")
        )
    }

    private func makeRuntime(
        dshVersion: String,
        webVersion: String,
        sourceCommit: String = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"
    ) throws -> (root: URL, runtime: HostRuntimeConfiguration, catalog: SupportedHostBuildCatalog) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-post-handshake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let node = root.appendingPathComponent("node")
        FileManager.default.createFile(atPath: node.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

        let entry = root.appendingPathComponent("payload/node_modules/@deepseek-ai/dsh/lib/cli.js")
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: entry.path, contents: Data())
        let dshManifest = entry.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("package.json")
        try Data("{\"version\":\"\(dshVersion)\"}".utf8).write(to: dshManifest)

        let webManifest = root.appendingPathComponent("payload/node_modules/@deepseek-ai/dsh-web-frontend/package.json")
        try FileManager.default.createDirectory(at: webManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"version\":\"\(webVersion)\"}".utf8).write(to: webManifest)

        let build = SupportedHostBuildCatalog.Build(
            id: "dsh-0.1.2-rc.1-official-a66e470",
            officialSourceCommit: sourceCommit,
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
            verifiedAt: "2026-09-09",
            verificationState: "verified"
        )
        let catalog = SupportedHostBuildCatalog(schemaVersion: 1, defaultBuildId: build.id, builds: [build])
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: node,
            dshEntrypoint: entry,
            homeDirectory: root.appendingPathComponent("home", isDirectory: true),
            logFile: root.appendingPathComponent("logs/host.log")
        )
        return (root, runtime, catalog)
    }
}
