import XCTest
@testable import GlassCore

final class GhostPlaneResponsePolicyTests: XCTestCase {
    func testAllowsRc1ComboScriptAndSourceMapMimes() throws {
        let policy = try makePolicy()
        let script = URL(string: "http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=r1")!
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "text/javascript; charset=utf-8"), .allowPluginCombo(pluginIDs: ["@deepseek-ai/dsh-ui-chat"], sourceMap: false))
        let map = URL(string: "http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js.map&rev=r1")!
        XCTAssertEqual(policy.decision(requestURL: map, responseURL: map, statusCode: 200, mimeType: "application/json"), .allowPluginCombo(pluginIDs: ["@deepseek-ai/dsh-ui-chat"], sourceMap: true))
    }

    func testRejectsRedirectStatusAndComboMimeConfusion() throws {
        let policy = try makePolicy()
        let script = URL(string: "http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=r1")!
        let other = URL(string: "http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=r2")!
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: other, statusCode: 200, mimeType: "text/javascript"), .deny(.redirect))
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: script, statusCode: 404, mimeType: "text/javascript"), .deny(.nonSuccessStatus))
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "application/json"), .deny(.unexpectedMIMEType))
    }

    private func makePolicy() throws -> GhostPlaneResponsePolicy {
        .init(loopback: try XCTUnwrap(GhostPlaneLoopbackPolicy(origin: URL(string: "http://127.0.0.1:7342/")!, pluginIDs: ["@deepseek-ai/dsh-ui-chat"])))
    }
}
