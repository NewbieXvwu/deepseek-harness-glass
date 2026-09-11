import XCTest
@testable import GlassUI

final class GlassPolicyTests: XCTestCase {
    func testOnlyReviewedPoliciesPermitCustomGlassEffects() {
        XCTAssertFalse(GlassPolicy.content.permitsCustomGlassEffect)
        XCTAssertFalse(GlassPolicy.systemNavigation.permitsCustomGlassEffect)
        XCTAssertTrue(GlassPolicy.regularGlassCustomControl.permitsCustomGlassEffect)
    }

    func testCustomGlassBudgetAllowsOneAndRejectsTwoControls() {
        XCTAssertTrue(GlassPolicyBudget.permits([.content, .regularGlassCustomControl]))
        XCTAssertTrue(GlassPolicyBudget.permits([.systemNavigation, .content]))
        XCTAssertFalse(GlassPolicyBudget.permits([.regularGlassCustomControl, .regularGlassCustomControl]))
    }

    func testRuntimeMaterializationDecisionRejectsContentAndSystemNavigation() {
        XCTAssertTrue(NativeGlassEffectDecision.materializes(policy: .regularGlassCustomControl, isEnabled: true))
        XCTAssertFalse(NativeGlassEffectDecision.materializes(policy: .regularGlassCustomControl, isEnabled: false))
        XCTAssertFalse(NativeGlassEffectDecision.materializes(policy: .content, isEnabled: true))
        XCTAssertFalse(NativeGlassEffectDecision.materializes(policy: .systemNavigation, isEnabled: true))
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

    func testSidebarCollapseAnimationUsesStaticTransitionWhenMotionIsReduced() {
        XCTAssertNotNil(NativeSidebarCollapseAnimation.transition(reduceMotion: false))
        XCTAssertNil(NativeSidebarCollapseAnimation.transition(reduceMotion: true))
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
