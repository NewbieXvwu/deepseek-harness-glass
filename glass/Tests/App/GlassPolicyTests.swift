import XCTest
@testable import GlassUI

final class GlassPolicyTests: XCTestCase {
    func testOnlyReviewedPoliciesPermitCustomGlassEffects() {
        XCTAssertFalse(GlassPolicy.content.permitsCustomGlassEffect)
        XCTAssertFalse(GlassPolicy.systemNavigation.permitsCustomGlassEffect)
        XCTAssertTrue(GlassPolicy.regularGlassCustomControl.permitsCustomGlassEffect)
        XCTAssertTrue(GlassPolicy.clearGlassMediaOverlay.permitsCustomGlassEffect)
    }

    func testSystemNavigationOwnsStructuralMaterial() {
        XCTAssertTrue(GlassPolicy.systemNavigation.ownsSystemNavigationMaterial)
        XCTAssertFalse(GlassPolicy.content.ownsSystemNavigationMaterial)
        XCTAssertFalse(GlassPolicy.regularGlassCustomControl.ownsSystemNavigationMaterial)
        XCTAssertFalse(GlassPolicy.clearGlassMediaOverlay.ownsSystemNavigationMaterial)
    }

    func testCustomGlassBudgetAllowsOneAndRejectsTwoControls() {
        XCTAssertTrue(GlassPolicyBudget.permits([.content, .regularGlassCustomControl]))
        XCTAssertTrue(GlassPolicyBudget.permits([.systemNavigation, .content]))
        XCTAssertFalse(GlassPolicyBudget.permits([.regularGlassCustomControl, .clearGlassMediaOverlay]))
    }
}
