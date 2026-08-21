import XCTest
@testable import GlassCore

final class GhostPlaneContentSecurityPolicyTests: XCTestCase {
    func testFixedPolicyIsInsertedIntoNativeHead() throws {
        let html = try XCTUnwrap(GhostPlaneContentSecurityPolicy.inject(into: "<html><head data-native=\"1\"></head><body></body></html>"))
        XCTAssertTrue(html.contains("<head data-native=\"1\"><meta http-equiv=\"Content-Security-Policy\""))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("form-action 'none'"))
        XCTAssertTrue(html.contains("script-src 'self'"))
    }

    func testFragmentWithoutHeadCannotBecomeGhostPlaneDocument() {
        XCTAssertNil(GhostPlaneContentSecurityPolicy.inject(into: "<div id=\"ghost-plane-root\"></div>"))
    }
}
