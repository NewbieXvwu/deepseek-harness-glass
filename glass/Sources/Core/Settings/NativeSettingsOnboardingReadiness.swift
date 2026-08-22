import Foundation

/// Foundation-only projection of rc.2 Models settings onboarding readiness.
/// It accepts already-joined Host facts; callers must not infer a credential
/// reference from provider names or synthesize a configured state after errors.
public enum NativeSettingsOnboardingReadiness: Equatable, Sendable {
    public enum LoadStatus: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed
    }

    public enum UnavailableReason: Equatable, Sendable {
        case loadFailed
        case providerInactive
        case credentialsUnavailable
        case settingsReadOnly
        case credentialReadOnly
    }

    public enum Result: Equatable, Sendable {
        case loading
        case adapterAbsent
        case providerReady
        case credentialMissing
        case unavailable(UnavailableReason)
    }

    public struct Credential: Equatable, Sendable {
        public let configured: Bool
        public let writable: Bool

        public init(configured: Bool, writable: Bool) {
            self.configured = configured
            self.writable = writable
        }
    }

    /// One provider row after the Models settings join. `credentialReference`
    /// is nil only when the resolved Host profile names no credential reference.
    public struct Provider: Equatable, Sendable {
        public let provider: String
        public let settingsNamespace: String
        public let settingsPath: [String]
        public let active: Bool
        public let credentialReference: String?
        public let credential: Credential?

        public init(
            provider: String,
            settingsNamespace: String,
            settingsPath: [String],
            active: Bool,
            credentialReference: String?,
            credential: Credential?
        ) {
            self.provider = provider
            self.settingsNamespace = settingsNamespace
            self.settingsPath = settingsPath
            self.active = active
            self.credentialReference = credentialReference
            self.credential = credential
        }
    }

    public struct Input: Equatable, Sendable {
        public let status: LoadStatus
        public let credentialReadFailed: Bool
        public let settingsWritable: Bool
        public let providers: [Provider]

        public init(
            status: LoadStatus,
            credentialReadFailed: Bool,
            settingsWritable: Bool,
            providers: [Provider]
        ) {
            self.status = status
            self.credentialReadFailed = credentialReadFailed
            self.settingsWritable = settingsWritable
            self.providers = providers
        }
    }

    /// A registered active provider can serve immediately if its resolved profile
    /// has no credential reference, or if its required Host credential is stored.
    public static func providerUsable(_ provider: Provider) -> Bool {
        guard provider.active else { return false }
        guard provider.credentialReference != nil else { return true }
        return provider.credential?.configured == true
    }

    /// Exact rc.2 onboarding precedence. Any usable provider ends onboarding;
    /// otherwise only the configurable official DeepSeek route determines whether
    /// prompting for a credential could help.
    public static func resolve(_ input: Input) -> Result {
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
        guard official.active else {
            return .unavailable(.providerInactive)
        }
        guard !input.credentialReadFailed, let credential = official.credential else {
            return .unavailable(.credentialsUnavailable)
        }
        guard input.settingsWritable else {
            return .unavailable(.settingsReadOnly)
        }
        guard credential.writable else {
            return .unavailable(.credentialReadOnly)
        }
        return .credentialMissing
    }
}
