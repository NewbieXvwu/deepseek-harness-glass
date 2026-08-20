import XCTest
@testable import GlassUI

final class GlassPolicyTests: XCTestCase {
    func testOnlyReviewedPoliciesPermitCustomGlassEffects() {
        XCTAssertFalse(GlassPolicy.content.permitsCustomGlassEffect)
        XCTAssertFalse(GlassPolicy.systemNavigation.permitsCustomGlassEffect)
        XCTAssertTrue(GlassPolicy.regularGlassCustomControl.permitsCustomGlassEffect)
        XCTAssertFalse(GlassPolicy.clearGlassMediaOverlay.permitsCustomGlassEffect)
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
        XCTAssertFalse(GlassPolicyBudget.permits([.regularGlassCustomControl, .regularGlassCustomControl]))
        XCTAssertTrue(
            GlassPolicyBudget.permits([.regularGlassCustomControl, .clearGlassMediaOverlay]),
            "a reserved, non-materializing overlay must not consume an approved control budget"
        )
    }

    func testRuntimeMaterializationDecisionRejectsContentAndUnreviewedPolicies() {
        XCTAssertTrue(NativeGlassEffectDecision.materializes(policy: .regularGlassCustomControl, isEnabled: true))
        XCTAssertFalse(NativeGlassEffectDecision.materializes(policy: .regularGlassCustomControl, isEnabled: false))
        XCTAssertFalse(NativeGlassEffectDecision.materializes(policy: .content, isEnabled: true))
        XCTAssertFalse(NativeGlassEffectDecision.materializes(policy: .systemNavigation, isEnabled: true))
        XCTAssertFalse(NativeGlassEffectDecision.materializes(policy: .clearGlassMediaOverlay, isEnabled: true))
    }

    func testAccessibilityPolicyDisablesCustomGlassForTransparencyAndContrast() {
        XCTAssertTrue(NativeGlassControlAccessibilityPolicy.permitsCustomGlass(
            reduceTransparency: false,
            contrast: .standard
        ))
        XCTAssertFalse(NativeGlassControlAccessibilityPolicy.permitsCustomGlass(
            reduceTransparency: true,
            contrast: .standard
        ))
        XCTAssertFalse(NativeGlassControlAccessibilityPolicy.permitsCustomGlass(
            reduceTransparency: false,
            contrast: .increased
        ))
    }

    func testAccessibilityPolicyDisablesMorphingWhenMotionIsReduced() {
        XCTAssertTrue(NativeGlassControlAccessibilityPolicy.permitsMorphing(reduceMotion: false))
        XCTAssertFalse(NativeGlassControlAccessibilityPolicy.permitsMorphing(reduceMotion: true))
    }

    func testNavigationAnimationDisablesMorphingWhenMotionIsReduced() {
        XCTAssertNotNil(NativeGlassNavigationAnimation.pressedAnimation(reduceMotion: false))
        XCTAssertNil(NativeGlassNavigationAnimation.pressedAnimation(reduceMotion: true))
    }

    func testNavigationBackgroundUsesOfficialFillWhenCustomGlassIsNotAccessible() {
        XCTAssertEqual(
            NativeGlassNavigationBackground.resolve(reduceTransparency: false, contrast: .standard),
            .customMaterial
        )
        XCTAssertEqual(
            NativeGlassNavigationBackground.resolve(reduceTransparency: true, contrast: .standard),
            .officialTokenFill
        )
        XCTAssertEqual(
            NativeGlassNavigationBackground.resolve(reduceTransparency: false, contrast: .increased),
            .officialTokenFill
        )
    }
}
