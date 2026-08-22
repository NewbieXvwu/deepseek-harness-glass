import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeSettingsOnboardingLedgerPortableCheck {
    static func main() throws {
        let registrations = [
            NativeSettingsOnboardingStep(id: "deepseek-official", order: 0),
            NativeSettingsOnboardingStep(id: "welcome-notice", order: -100),
            NativeSettingsOnboardingStep(id: "equal-first", order: 10),
            NativeSettingsOnboardingStep(id: "equal-second", order: 10),
        ]
        guard NativeSettingsOnboardingLedger.ordered(registrations).map(\.id) == [
            "welcome-notice", "deepseek-official", "equal-first", "equal-second",
        ] else {
            throw CheckFailure(description: "onboarding ledger must keep rc.2 order and equal-order registration sequence")
        }
        let welcomeCompleted: Set<String> = ["welcome-notice"]
        guard NativeSettingsOnboardingLedger.activeStep(
            isOnboardingActive: true,
            registrations: registrations,
            completedIDs: welcomeCompleted
        )?.id == "deepseek-official" else {
            throw CheckFailure(description: "onboarding must mount exactly the first unfinished step")
        }
        guard NativeSettingsOnboardingLedger.activeStep(
            isOnboardingActive: false,
            registrations: registrations,
            completedIDs: []
        ) == nil else {
            throw CheckFailure(description: "non-welcome sessions must not mount onboarding chrome")
        }
        let stale = NativeSettingsOnboardingLedger.completing(
            id: "equal-first",
            activeStepID: "deepseek-official",
            completedIDs: welcomeCompleted
        )
        guard stale == welcomeCompleted else {
            throw CheckFailure(description: "a stale/non-mounted step must not skip the active onboarding owner")
        }
        let completed = NativeSettingsOnboardingLedger.completing(
            id: "deepseek-official",
            activeStepID: "deepseek-official",
            completedIDs: welcomeCompleted
        )
        guard completed == ["welcome-notice", "deepseek-official"],
              NativeSettingsOnboardingLedger.resettingWhenInactive(
                isOnboardingActive: false,
                completedIDs: completed
              ).isEmpty else {
            throw CheckFailure(description: "active completion and inactive reset must match rc.2 state lifetime")
        }
        print("native settings onboarding ledger portable check passed")
    }
}
