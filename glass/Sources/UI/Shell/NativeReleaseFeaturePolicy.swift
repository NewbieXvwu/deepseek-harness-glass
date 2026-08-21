/// Release-time visibility policy for high-risk native surfaces. It controls
/// registration at the shell boundary, so disabled features cannot leave a
/// reachable tab or header action behind a partially implemented renderer.
struct NativeReleaseFeaturePolicy: Equatable {
    enum Surface: String, CaseIterable {
        case trajectoryTab
        case subagentCatalogAction
    }

    struct Rule: Equatable {
        let isEnabled: Bool
        let owner: String
        let expiryCondition: String
        let deletionPlan: String
    }

    private let rules: [Surface: Rule]

    init(rules: [Surface: Rule]) {
        self.rules = rules
    }

    func permits(_ surface: Surface) -> Bool {
        rules[surface]?.isEnabled ?? false
    }

    func rule(for surface: Surface) -> Rule? {
        rules[surface]
    }

    /// Production default: high-risk complex surfaces stay absent until their
    /// host-authority, plugin fallback, keyboard/AX, visual, and performance
    /// acceptance evidence is complete. Chat remains registry-owned and always
    /// present independently of this policy.
    static let releaseCandidate = NativeReleaseFeaturePolicy(rules: [
        .trajectoryTab: .init(
            isEnabled: false,
            owner: "native-conversation",
            expiryCondition: "T9.5 and T12.4-T12.6 complete with macOS runtime evidence",
            deletionPlan: "Delete this rule and register trajectory unconditionally after acceptance."
        ),
        .subagentCatalogAction: .init(
            isEnabled: false,
            owner: "native-subagents",
            expiryCondition: "T9.5 and T12.5-T12.7 complete with plugin isolation evidence",
            deletionPlan: "Delete this rule and register the catalog action unconditionally after acceptance."
        ),
    ])

    /// Test/snapshot opt-in for approved renderer coverage. This is never the
    /// production default and makes enabled state explicit in every fixture.
    static let allEnabled = NativeReleaseFeaturePolicy(rules: [
        .trajectoryTab: .init(
            isEnabled: true,
            owner: "native-conversation",
            expiryCondition: "test-only override",
            deletionPlan: "test-only override"
        ),
        .subagentCatalogAction: .init(
            isEnabled: true,
            owner: "native-subagents",
            expiryCondition: "test-only override",
            deletionPlan: "test-only override"
        ),
    ])
}
