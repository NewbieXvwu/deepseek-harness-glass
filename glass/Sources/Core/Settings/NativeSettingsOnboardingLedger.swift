import Foundation

/// A reviewed `settings.onboarding` registration. The shell owns session-state
/// admission; a step owns whether it paints chrome or completes itself.
public struct NativeSettingsOnboardingStep: Equatable, Sendable, Identifiable {
    public let id: String
    public let order: Int

    public init(id: String, order: Int) {
        self.id = id
        self.order = order
    }
}

/// Foundation-only equivalent of rc.2 SettingsRoot onboarding selection.
/// It deliberately has no modal, credential, or UI dependency: registrants
/// retain visible-chrome/readiness ownership and unadmitted steps paint nothing.
public enum NativeSettingsOnboardingLedger {
    /// JS stable `Array.prototype.sort(order)` equivalent. Equal-order entries
    /// retain ledger registration order rather than being reordered by id.
    public static func ordered(_ registrations: [NativeSettingsOnboardingStep]) -> [NativeSettingsOnboardingStep] {
        registrations.enumerated()
            .sorted { lhs, rhs in
                lhs.element.order == rhs.element.order ? lhs.offset < rhs.offset : lhs.element.order < rhs.element.order
            }
            .map(\.element)
    }

    /// Mirrors `onboardingActive ? steps.find(!completed.has(id)) : undefined`.
    /// Session state outside its welcome scope must mount no step.
    public static func activeStep(
        isOnboardingActive: Bool,
        registrations: [NativeSettingsOnboardingStep],
        completedIDs: Set<String>
    ) -> NativeSettingsOnboardingStep? {
        guard isOnboardingActive else { return nil }
        return ordered(registrations).first { !completedIDs.contains($0.id) }
    }

    /// The completion callback is bound to the currently mounted step. Reject
    /// stale/unregistered callers so they cannot skip the first pending step.
    public static func completing(
        id: String,
        activeStepID: String?,
        completedIDs: Set<String>
    ) -> Set<String> {
        guard id == activeStepID, !completedIDs.contains(id) else { return completedIDs }
        return completedIDs.union([id])
    }

    /// rc.2 clears in-memory completion when the welcome session state ends.
    public static func resettingWhenInactive(isOnboardingActive: Bool, completedIDs: Set<String>) -> Set<String> {
        isOnboardingActive ? completedIDs : []
    }
}
