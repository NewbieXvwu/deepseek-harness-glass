import XCTest

@testable import GlassCore

final class NativeSettingsOnboardingReadinessTests: XCTestCase {
    private typealias Readiness = NativeSettingsOnboardingReadiness

    private func official(
        active: Bool = true,
        credentialReference: String? = "DEEPSEEK_API_KEY",
        credential: Readiness.Credential? = .init(configured: false, writable: true)
    ) -> Readiness.Provider {
        .init(
            provider: "deepseek-official",
            settingsNamespace: "llm-deepseek",
            settingsPath: [],
            active: active,
            credentialReference: credentialReference,
            credential: credential
        )
    }

    private func input(
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

    func testLoadingAndAdapterAdmissionMatchOfficialJoin() {
        XCTAssertEqual(Readiness.resolve(input(status: .idle)), .loading)
        XCTAssertEqual(Readiness.resolve(input(status: .loading)), .loading)
        XCTAssertEqual(Readiness.resolve(input()), .adapterAbsent)
        XCTAssertEqual(
            Readiness.resolve(input(providers: [.init(
                provider: "deepseek-official",
                settingsNamespace: "",
                settingsPath: [],
                active: true,
                credentialReference: nil,
                credential: nil
            )])),
            // An active deepseek-official provider without a credential reference
            // is immediately usable: onboarding ends (providerReady).
            .providerReady
        )
    }

    func testAnyUsableProviderEndsOnboardingAndInactiveCannot() {
        let other = Readiness.Provider(
            provider: "other",
            settingsNamespace: "llm-other",
            settingsPath: ["providers", "other"],
            active: true,
            credentialReference: "OTHER_KEY",
            credential: .init(configured: true, writable: true)
        )
        XCTAssertTrue(Readiness.providerUsable(other))
        XCTAssertEqual(Readiness.resolve(input(providers: [official(), other])), .providerReady)
        XCTAssertTrue(Readiness.providerUsable(.init(
            provider: "native-auth",
            settingsNamespace: "llm-native",
            settingsPath: [],
            active: true,
            credentialReference: nil,
            credential: nil
        )))
        XCTAssertFalse(Readiness.providerUsable(.init(
            provider: "inactive",
            settingsNamespace: "llm-inactive",
            settingsPath: [],
            active: false,
            credentialReference: nil,
            credential: nil
        )))
    }

    func testOfficialRouteReadinessUnavailablePrecedenceAndCredentialMissing() {
        XCTAssertEqual(Readiness.resolve(input(status: .failed, providers: [official()])), .unavailable(.loadFailed))
        XCTAssertEqual(Readiness.resolve(input(providers: [official(active: false)])), .unavailable(.providerInactive))
        XCTAssertEqual(Readiness.resolve(input(credentialReadFailed: true, providers: [official()])), .unavailable(.credentialsUnavailable))
        XCTAssertEqual(Readiness.resolve(input(providers: [official(credential: nil)])), .unavailable(.credentialsUnavailable))
        XCTAssertEqual(Readiness.resolve(input(settingsWritable: false, providers: [official()])), .unavailable(.settingsReadOnly))
        XCTAssertEqual(
            Readiness.resolve(input(providers: [official(credential: .init(configured: false, writable: false))])),
            .unavailable(.credentialReadOnly)
        )
        XCTAssertEqual(Readiness.resolve(input(providers: [official()])), .credentialMissing)
    }
}
