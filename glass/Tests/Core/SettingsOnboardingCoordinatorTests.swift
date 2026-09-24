import XCTest
@testable import GlassCore

final class SettingsOnboardingCoordinatorTests: XCTestCase {
    private let coordinator = SettingsOnboardingCoordinator()

    private func official(
        active: Bool = true,
        credentialReference: String? = "DEEPSEEK_API_KEY",
        credential: SettingsOnboardingCoordinator.Credential? = .init(configured: false, writable: true)
    ) -> SettingsOnboardingCoordinator.Provider {
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
        status: SettingsOnboardingCoordinator.LoadStatus = .ready,
        credentialReadFailed: Bool = false,
        settingsWritable: Bool = true,
        providers: [SettingsOnboardingCoordinator.Provider] = []
    ) -> SettingsOnboardingCoordinator.ReadinessInput {
        .init(
            status: status,
            credentialReadFailed: credentialReadFailed,
            settingsWritable: settingsWritable,
            providers: providers
        )
    }

    func testLedgerUsesStableOrderAndMountedStepAdmission() {
        let registrations = [
            SettingsOnboardingStep(id: "deepseek-official", order: 0),
            SettingsOnboardingStep(id: "welcome-notice", order: -100),
            SettingsOnboardingStep(id: "same-order-first", order: 10),
            SettingsOnboardingStep(id: "same-order-second", order: 10),
        ]
        XCTAssertEqual(
            coordinator.ordered(registrations).map(\.id),
            ["welcome-notice", "deepseek-official", "same-order-first", "same-order-second"]
        )
        XCTAssertEqual(
            coordinator.activeStep(
                isOnboardingActive: true,
                registrations: registrations,
                completedIDs: ["welcome-notice"]
            )?.id,
            "deepseek-official"
        )
        XCTAssertNil(coordinator.activeStep(
            isOnboardingActive: false,
            registrations: registrations,
            completedIDs: []
        ))

        let initial: Set<String> = ["welcome-notice"]
        XCTAssertEqual(
            coordinator.completing(
                id: "same-order-first",
                activeStepID: "deepseek-official",
                completedIDs: initial
            ),
            initial
        )
        let completed = coordinator.completing(
            id: "deepseek-official",
            activeStepID: "deepseek-official",
            completedIDs: initial
        )
        XCTAssertEqual(completed, ["welcome-notice", "deepseek-official"])
        XCTAssertEqual(
            coordinator.resettingWhenInactive(isOnboardingActive: false, completedIDs: completed),
            []
        )
    }

    func testReadinessUsesJoinedHostFactsOnly() {
        XCTAssertEqual(coordinator.readiness(input(status: .idle)), .loading)
        XCTAssertEqual(coordinator.readiness(input()), .adapterAbsent)

        let other = SettingsOnboardingCoordinator.Provider(
            provider: "other",
            settingsNamespace: "llm-other",
            settingsPath: ["providers", "other"],
            active: true,
            credentialReference: "OTHER_KEY",
            credential: .init(configured: true, writable: true)
        )
        XCTAssertTrue(coordinator.providerUsable(other))
        XCTAssertEqual(coordinator.readiness(input(providers: [official(), other])), .providerReady)
        XCTAssertEqual(
            coordinator.readiness(input(providers: [official(active: false)])),
            .unavailable(.providerInactive)
        )
        XCTAssertEqual(
            coordinator.readiness(input(credentialReadFailed: true, providers: [official()])),
            .unavailable(.credentialsUnavailable)
        )
        XCTAssertEqual(
            coordinator.readiness(input(settingsWritable: false, providers: [official()])),
            .unavailable(.settingsReadOnly)
        )
        XCTAssertEqual(coordinator.readiness(input(providers: [official()])), .credentialMissing)
    }
}
