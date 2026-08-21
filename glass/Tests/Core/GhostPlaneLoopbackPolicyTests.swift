@testable import GlassCore

final class GhostPlaneLoopbackPolicyTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:7342/")!

    func testPolicyAdmitsOnlyRegisteredSameOriginPluginPaths() throws {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: origin,
            pluginIDs: ["dsh-review-loop", "dsh.open_in_vscode"]
        ))

        XCTAssertEqual(
            policy.decision(for: URL(string: "http://127.0.0.1:7342/plugins/dsh-review-loop/client.js")!),
            .allowPluginResource(pluginID: "dsh-review-loop")
        )
        XCTAssertEqual(
            policy.pluginRootURL(for: "dsh.open_in_vscode")?.absoluteString,
            "http://127.0.0.1:7342/plugins/dsh.open_in_vscode/"
        )
        XCTAssertNil(policy.pluginRootURL(for: "third-party"))
    }

    func testPolicyRejectsNonPluginAndUnsafeRequestsBeforeNavigation() throws {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(origin: origin, pluginIDs: ["dsh-review-loop"]))
        let cases: [(String, GhostPlaneLoopbackPolicy.Denial)] = [
            ("https://127.0.0.1:7342/plugins/dsh-review-loop/client.js", .unsupportedScheme),
            ("file:///tmp/client.js", .unsupportedScheme),
            ("http://plugin.example/plugins/dsh-review-loop/client.js", .nonLoopbackHost),
            ("http://127.0.0.1:7343/plugins/dsh-review-loop/client.js", .wrongPort),
            ("http://credential@127.0.0.1:7342/plugins/dsh-review-loop/client.js", .credentialedURL),
            ("http://127.0.0.1:7342/plugins/unknown/client.js", .unregisteredPlugin),
            ("http://127.0.0.1:7342/api/host.describe", .nonPluginPath),
            ("http://127.0.0.1:7342/plugins/dsh-review-loop/%2e%2e/client.js", .encodedTraversal),
        ]

        for (raw, denial) in cases {
            XCTAssertEqual(policy.decision(for: try XCTUnwrap(URL(string: raw))), .deny(denial), raw)
        }
    }

    func testPolicyConstructionRejectsNonCanonicalOrUnsafeBoundary() {
        XCTAssertNil(GhostPlaneLoopbackPolicy(origin: URL(string: "https://127.0.0.1:7342/")!, pluginIDs: []))
        XCTAssertNil(GhostPlaneLoopbackPolicy(origin: URL(string: "http://localhost:7342/")!, pluginIDs: []))
        XCTAssertNil(GhostPlaneLoopbackPolicy(origin: URL(string: "http://user@127.0.0.1:7342/")!, pluginIDs: []))
        XCTAssertNil(GhostPlaneLoopbackPolicy(origin: URL(string: "http://127.0.0.1:0/")!, pluginIDs: []))
        XCTAssertNil(GhostPlaneLoopbackPolicy(origin: origin, pluginIDs: ["<unsafe>"]))
    }
}
