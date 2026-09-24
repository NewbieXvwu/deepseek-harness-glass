import Foundation

struct SettingsOnboardingStep: Equatable, Sendable, Identifiable {
    let id: String
    let order: Int
}

/// Owns the in-memory admission/completion ledger and the Host-fact readiness
/// join for settings onboarding. It has no UI, transport, or secret-value state.
struct SettingsOnboardingCoordinator: Sendable {
    enum LoadStatus: Equatable, Sendable { case idle, loading, ready, failed }

    enum UnavailableReason: Equatable, Sendable {
        case loadFailed
        case providerInactive
        case credentialsUnavailable
        case settingsReadOnly
        case credentialReadOnly
    }

    enum Readiness: Equatable, Sendable {
        case loading
        case adapterAbsent
        case providerReady
        case credentialMissing
        case unavailable(UnavailableReason)
    }

    struct Credential: Equatable, Sendable {
        let configured: Bool
        let writable: Bool
    }

    struct Provider: Equatable, Sendable {
        let provider: String
        let settingsNamespace: String
        let settingsPath: [String]
        let active: Bool
        let credentialReference: String?
        let credential: Credential?
    }

    struct ReadinessInput: Equatable, Sendable {
        let status: LoadStatus
        let credentialReadFailed: Bool
        let settingsWritable: Bool
        let providers: [Provider]
    }

    func ordered(_ registrations: [SettingsOnboardingStep]) -> [SettingsOnboardingStep] {
        registrations.enumerated()
            .sorted { lhs, rhs in
                lhs.element.order == rhs.element.order ? lhs.offset < rhs.offset : lhs.element.order < rhs.element.order
            }
            .map(\.element)
    }

    func activeStep(
        isOnboardingActive: Bool,
        registrations: [SettingsOnboardingStep],
        completedIDs: Set<String>
    ) -> SettingsOnboardingStep? {
        guard isOnboardingActive else { return nil }
        return ordered(registrations).first { !completedIDs.contains($0.id) }
    }

    func completing(id: String, activeStepID: String?, completedIDs: Set<String>) -> Set<String> {
        guard id == activeStepID, !completedIDs.contains(id) else { return completedIDs }
        return completedIDs.union([id])
    }

    func resettingWhenInactive(isOnboardingActive: Bool, completedIDs: Set<String>) -> Set<String> {
        isOnboardingActive ? completedIDs : []
    }

    func providerUsable(_ provider: Provider) -> Bool {
        guard provider.active else { return false }
        guard provider.credentialReference != nil else { return true }
        return provider.credential?.configured == true
    }

    func readiness(_ input: ReadinessInput) -> Readiness {
        if (input.status == .idle || input.status == .loading), input.providers.isEmpty {
            return .loading
        }
        if input.status == .failed {
            return .unavailable(.loadFailed)
        }
        if input.providers.contains(where: providerUsable) {
            return .providerReady
        }
        guard let official = input.providers.first(where: {
            $0.provider == "deepseek-official"
                && $0.settingsNamespace == "llm-deepseek"
                && $0.settingsPath.isEmpty
        }) else {
            return .adapterAbsent
        }
        guard official.active else { return .unavailable(.providerInactive) }
        guard !input.credentialReadFailed, let credential = official.credential else {
            return .unavailable(.credentialsUnavailable)
        }
        guard input.settingsWritable else { return .unavailable(.settingsReadOnly) }
        guard credential.writable else { return .unavailable(.credentialReadOnly) }
        return .credentialMissing
    }
}
