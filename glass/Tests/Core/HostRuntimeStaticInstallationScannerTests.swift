import XCTest
@testable import GlassCore

final class HostRuntimeStaticInstallationScannerTests: XCTestCase {
    func testScannerRequiresCompleteStaticResourceLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let node = root.appendingPathComponent("node/node")
        let entry = root.appendingPathComponent("backend/node_modules/@deepseek-ai/dsh/lib/bin.js")
        let catalog = root.appendingPathComponent("SupportedHostBuilds.json")
        try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: node.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        _ = FileManager.default.createFile(atPath: entry.path, contents: Data())
        _ = FileManager.default.createFile(atPath: catalog.path, contents: Data("{}".utf8))
        XCTAssertEqual(HostRuntimeStaticInstallationScanner().scan(resourcesRoots: [root, root]).count, 1)
        try FileManager.default.removeItem(at: catalog)
        XCTAssertTrue(HostRuntimeStaticInstallationScanner().scan(resourcesRoots: [root]).isEmpty)
    }
}
