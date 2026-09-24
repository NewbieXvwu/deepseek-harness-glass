struct NativeReleaseFeaturePolicy: Sendable {
    enum Surface: String, Hashable, Sendable {
        case trajectoryTab
        case subagentCatalogAction
    }

    private let enabledSurfaces: Set<Surface>

    init(enabledSurfaces: Set<Surface>) {
        self.enabledSurfaces = enabledSurfaces
    }

    static let releaseCandidate = NativeReleaseFeaturePolicy(enabledSurfaces: [])

    func permits(_ surface: Surface) -> Bool {
        enabledSurfaces.contains(surface)
    }
}
