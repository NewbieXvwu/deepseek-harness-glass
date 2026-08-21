import XCTest
@testable import GlassCore

final class GhostPlaneResponsePolicyTests: XCTestCase {
    func testAllowsExactSuccessfulSkeletonAndJavaScriptResponses() throws {
        let policy = try makePolicy()
        let skeleton = URL(string: "http://127.0.0.1:7342/")!
        XCTAssertEqual(policy.decision(requestURL: skeleton, responseURL: skeleton, statusCode: 200, mimeType: "text/html; charset=utf-8"), .allowSkeletonDocument)
        let script = URL(string: "http://127.0.0.1:7342/plugins/dsh-review/client.js?rev=r1")!
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "application/javascript"), .allowPluginResource(pluginID: "dsh-review"))
    }

    func testRejectsRedirectsStatusAndMIMEConfusion() throws {
        let policy = try makePolicy()
        let script = URL(string: "http://127.0.0.1:7342/plugins/dsh-review/client.js?rev=r1")!
        let redirected = URL(string: "http://127.0.0.1:7342/plugins/dsh-review/other.js?rev=r1")!
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: redirected, statusCode: 200, mimeType: "application/javascript"), .deny(.redirect))
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: script, statusCode: 302, mimeType: "application/javascript"), .deny(.nonSuccessStatus))
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "text/html"), .deny(.unexpectedMIMEType))
        XCTAssertEqual(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "text/css"), .deny(.pathMIMEMismatch))
        let svg = URL(string: "http://127.0.0.1:7342/plugins/dsh-review/icon.svg")!
        XCTAssertEqual(policy.decision(requestURL: svg, responseURL: svg, statusCode: 200, mimeType: "image/svg+xml"), .deny(.unexpectedMIMEType))
    }

    private func makePolicy() throws -> GhostPlaneResponsePolicy {
        let loopback = try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!, pluginIDs: ["dsh-review"]
        ))
        return .init(loopback: loopback)
    }
}
