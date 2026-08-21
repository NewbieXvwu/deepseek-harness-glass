import Foundation

enum OfficialUISpec {
    enum Build {
        static let sourceCommit = "528c682e061696f5a160f363f236ecbf53cbd006"
    }
}

struct OfficialColumnLayout {
    let sidebar: CGFloat
    let center: CGFloat
    let details: CGFloat

    static func resolve(viewport: CGFloat, sidebarPreference: CGFloat, detailsPreference: CGFloat) -> Self {
        .init(sidebar: sidebarPreference, center: max(0, viewport - sidebarPreference - detailsPreference), details: detailsPreference)
    }
}

@main
struct OfficialGhostPlaneContractPortableCheck {
    static func main() throws {
        let loader = OfficialGhostPlaneContract.Fixture.ModuleLoader(
            bootGlobal: "__DSH_BOOT__",
            registrationGlobal: "__ModuleLoader__",
            registrationMethod: "load",
            bundlePathTemplate: "/plugins/<id>/client.js?rev=<rev>",
            factoryRegistration: true
        )
        let fixture = OfficialGhostPlaneContract.Fixture(
            schemaVersion: 1,
            sourceCommit: OfficialUISpec.Build.sourceCommit,
            sources: [.init(path: "official/slots.ts", sha256: "sha256:fixture")],
            selectors: GhostPlaneSkeleton.requiredSelectors,
            slots: [.init(name: "conversation.session", kind: "single", scope: "session")],
            moduleLoader: loader
        )
        try OfficialGhostPlaneContract.validateSkeletonSelectors(GhostPlaneSkeleton.requiredSelectors, against: fixture)
        do {
            try OfficialGhostPlaneContract.validateSkeletonSelectors(["[data-conversation-scroll]"], against: fixture)
            throw CheckFailure("selector drift must fail")
        } catch let error as OfficialGhostPlaneContract.ValidationError {
            guard case .skeletonSelectorDrift = error else { throw error }
        }
        print("official ghost plane contract portable check passed")
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
