import Foundation
import XCTest
@testable import GlassCore

final class GhostPlaneLoopbackPolicyTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:7342/")!

    func testPolicyAdmitsRc1ComboScopedPackagesAndRegisteredAssets() throws {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: origin,
            pluginIDs: ["@deepseek-ai/dsh-ui-chat", "dsh-review-loop"]
        ))
        XCTAssertEqual(policy.decision(for: origin), .allowSkeletonDocument)
        let combo = try XCTUnwrap(URL(string: "http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js,dsh-review-loop/client.js&rev=batch-r1"))
        XCTAssertEqual(policy.decision(for: combo), .allowPluginCombo(pluginIDs: ["@deepseek-ai/dsh-ui-chat", "dsh-review-loop"], sourceMap: false))
        let map = try XCTUnwrap(URL(string: "http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js.map&rev=batch-r1"))
        XCTAssertEqual(policy.decision(for: map), .allowPluginCombo(pluginIDs: ["@deepseek-ai/dsh-ui-chat"], sourceMap: true))
        let asset = try XCTUnwrap(URL(string: "http://127.0.0.1:7342/plugins/@deepseek-ai/dsh-ui-chat/icon.png"))
        XCTAssertEqual(policy.decision(for: asset), .allowPluginResource(pluginID: "@deepseek-ai/dsh-ui-chat"))
    }

    func testPolicyRejectsUnsafeAndUnadvertisedComboRequests() throws {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(origin: origin, pluginIDs: ["@deepseek-ai/dsh-ui-chat"]))
        XCTAssertEqual(policy.decision(for: try XCTUnwrap(URL(string: "https://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=x"))), .deny(.unsupportedScheme))
        XCTAssertEqual(policy.decision(for: try XCTUnwrap(URL(string: "http://127.0.0.1:7342/plugins/??unknown/client.js&rev=x"))), .deny(.unregisteredPlugin))
        XCTAssertEqual(policy.decision(for: try XCTUnwrap(URL(string: "http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.css&rev=x"))), .deny(.malformedCombo))
        XCTAssertEqual(policy.decision(for: try XCTUnwrap(URL(string: "http://127.0.0.1:7342/api/remote.mux"))), .deny(.nonPluginPath))
    }

    func testPolicyConstructionAcceptsNpmPackageIDsAndRejectsUnsafeBoundary() {
        XCTAssertNotNil(GhostPlaneLoopbackPolicy(origin: origin, pluginIDs: ["@deepseek-ai/dsh-ui-chat", "plain-package"]))
        XCTAssertNil(GhostPlaneLoopbackPolicy(origin: origin, pluginIDs: ["@broken", "<unsafe>"]))
        XCTAssertNil(GhostPlaneLoopbackPolicy(origin: URL(string: "http://localhost:7342/")!, pluginIDs: []))
    }
}
