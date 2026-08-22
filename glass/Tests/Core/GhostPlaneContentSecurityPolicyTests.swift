import XCTest
@testable import GlassCore

final class GhostPlaneContentSecurityPolicyTests: XCTestCase {
    func testFixedPolicyIsInsertedIntoNativeHead() throws {
        let html = try XCTUnwrap(GhostPlaneContentSecurityPolicy.inject(into: "<html><head data-native=\"1\"></head><body></body></html>"))
        XCTAssertEqual(
            html,
            "<html><head data-native=\"1\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(GhostPlaneContentSecurityPolicy.value)\"></head><body></body></html>"
        )
    }

    func testFragmentWithoutHeadCannotBecomeGhostPlaneDocument() {
        XCTAssertNil(GhostPlaneContentSecurityPolicy.inject(into: "<div id=\"ghost-plane-root\"></div>"))
    }
}
