import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeSettingsOnboardingReadinessPortableCheck {
    typealias Readiness = NativeSettingsOnboardingReadiness

    static func official(
        active: Bool = true,
        credential: Readiness.Credential? = .init(configured: false, writable: true)
    ) -> Readiness.Provider {
        .init(
            provider: "deepseek-official",
            settingsNamespace: "llm-deepseek",
            settingsPath: [],
            active: active,
            credentialReference: "DEEPSEEK_API_KEY",
            credential: credential
        )
    }

    static func input(
        status: Readiness.LoadStatus = .ready,
        credentialReadFailed: Bool = false,
        settingsWritable: Bool = true,
        providers: [Readiness.Provider] = []
    ) -> Readiness.Input {
        .init(
            status: status,
            credentialReadFailed: credentialReadFailed,
            settingsWritable: settingsWritable,
            providers: providers
        )
    }

    static func main() throws {
        guard Readiness.resolve(input(status: .idle)) == .loading,
              Readiness.resolve(input()) == .adapterAbsent else {
            throw CheckFailure(description: "onboarding must preserve loading and adapter-absent admission")
        }
        let usable = Readiness.Provider(
            provider: "native-auth",
            settingsNamespace: "llm-native",
            settingsPath: [],
            active: true,
            credentialReference: nil,
            credential: nil
        )
        guard Readiness.providerUsable(usable),
              Readiness.resolve(input(providers: [official(), usable])) == .providerReady else {
            throw CheckFailure(description: "any active reference-free or configured provider must end onboarding")
        }
        guard Readiness.resolve(input(providers: [official(active: false)])) == .unavailable(.providerInactive),
              Readiness.resolve(input(credentialReadFailed: true, providers: [official()])) == .unavailable(.credentialsUnavailable),
              Readiness.resolve(input(settingsWritable: false, providers: [official()])) == .unavailable(.settingsReadOnly),
              Readiness.resolve(input(providers: [official(credential: .init(configured: false, writable: false))])) == .unavailable(.credentialReadOnly),
              Readiness.resolve(input(providers: [official()])) == .credentialMissing else {
            throw CheckFailure(description: "official route readiness precedence changed")
        }
        print("native settings onboarding readiness portable check passed")
    }
}
