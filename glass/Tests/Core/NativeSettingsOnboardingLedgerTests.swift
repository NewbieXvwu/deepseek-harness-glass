import XCTest

@testable import GlassCore

final class NativeSettingsOnboardingLedgerTests: XCTestCase {
    func testUsesStableOrderAndFirstIncompleteOnlyWhileWelcomeSessionIsActive() {
        let registrations = [
            NativeSettingsOnboardingStep(id: "deepseek-official", order: 0),
            NativeSettingsOnboardingStep(id: "welcome-notice", order: -100),
            NativeSettingsOnboardingStep(id: "same-order-first", order: 10),
            NativeSettingsOnboardingStep(id: "same-order-second", order: 10),
        ]
        XCTAssertEqual(
            NativeSettingsOnboardingLedger.ordered(registrations).map(\.id),
            ["welcome-notice", "deepseek-official", "same-order-first", "same-order-second"]
        )
        XCTAssertEqual(
            NativeSettingsOnboardingLedger.activeStep(
                isOnboardingActive: true,
                registrations: registrations,
                completedIDs: ["welcome-notice"]
            )?.id,
            "deepseek-official"
        )
        XCTAssertNil(NativeSettingsOnboardingLedger.activeStep(
            isOnboardingActive: false,
            registrations: registrations,
            completedIDs: []
        ))
    }

    func testOnlyMountedStepMayCompleteAndInactiveStateResetsCompletedIDs() {
        let initial: Set<String> = ["welcome-notice"]
        XCTAssertEqual(
            NativeSettingsOnboardingLedger.completing(
                id: "same-order-first",
                activeStepID: "deepseek-official",
                completedIDs: initial
            ),
            initial
        )
        let completed = NativeSettingsOnboardingLedger.completing(
            id: "deepseek-official",
            activeStepID: "deepseek-official",
            completedIDs: initial
        )
        XCTAssertEqual(completed, ["welcome-notice", "deepseek-official"])
        XCTAssertEqual(
            NativeSettingsOnboardingLedger.completing(
                id: "deepseek-official",
                activeStepID: "deepseek-official",
                completedIDs: completed
            ),
            completed
        )
        XCTAssertEqual(
            NativeSettingsOnboardingLedger.resettingWhenInactive(
                isOnboardingActive: true,
                completedIDs: completed
            ),
            completed
        )
        XCTAssertEqual(
            NativeSettingsOnboardingLedger.resettingWhenInactive(
                isOnboardingActive: false,
                completedIDs: completed
            ),
            []
        )
    }
}
