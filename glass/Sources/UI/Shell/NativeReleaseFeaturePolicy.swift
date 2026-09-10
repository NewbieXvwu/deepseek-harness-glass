import Foundation

struct NativeReleaseFeaturePolicy: Sendable {
    enum Feature: String, Hashable, Sendable {
        case trajectory
        case subagentCatalog
    }

    private let enabledFeatures: Set<Feature>

    init(enabledFeatures: Set<Feature>) {
        self.enabledFeatures = enabledFeatures
    }

    static let releaseCandidate = NativeReleaseFeaturePolicy(enabledFeatures: [])

    func isProductionEnabled(_ feature: Feature) -> Bool {
        enabledFeatures.contains(feature)
    }
}
