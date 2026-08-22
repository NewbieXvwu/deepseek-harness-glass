import Foundation

enum OfficialUISpec {
    enum Build {
        static let id = "dsh-0.1.1-rc.2-official-b150a55"
        static let sourceCommit = "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e"
        static func isCompatible(with buildID: String) -> Bool { buildID == id }
    }
}

@main
struct PluginRouteMatrixPortableCheck {
    static func main() throws {
        let router = PluginRouteMatrix()
        let adapterManifest = manifest(pluginID: "settings.shell")
        let adapterRequest = PluginRouteMatrix.Request(
            pluginID: "settings.shell", hostBuildID: OfficialUISpec.Build.id,
            profile: .sharedWeb, runtimeClass: .declarativeUI,
            manifestRoute: .native(adapterManifest), ghostPlaneAvailability: .admitted
        )
        guard case .swiftAdapter = router.destination(for: adapterRequest) else {
            throw Failure("reviewed adapter must outrank generic native manifest")
        }

        let genericManifest = manifest(pluginID: "example.plugin")
        let genericRequest = PluginRouteMatrix.Request(
            pluginID: "example.plugin", hostBuildID: OfficialUISpec.Build.id,
            profile: .sharedWeb, runtimeClass: .declarativeUI,
            manifestRoute: .native(genericManifest), ghostPlaneAvailability: .admitted
        )
        guard router.destination(for: genericRequest) == .nativeManifest(genericManifest) else {
            throw Failure("verified generic manifest must precede Ghost Plane")
        }

        let ghostRequest = PluginRouteMatrix.Request(
            pluginID: "example.plugin", hostBuildID: OfficialUISpec.Build.id,
            profile: .sharedWeb, runtimeClass: .sharedService,
            manifestRoute: .ghostPlaneFallback(pluginID: "example.plugin", reason: .integrityNotVerified),
            ghostPlaneAvailability: .admitted
        )
        guard router.destination(for: ghostRequest) == .ghostPlane(pluginID: "example.plugin") else {
            throw Failure("untrusted manifest must use admitted Ghost Plane fallback")
        }

        let blocked = PluginRouteMatrix.Request(
            pluginID: "example.plugin", hostBuildID: OfficialUISpec.Build.id,
            profile: .sharedWeb, runtimeClass: .exclusiveStdio,
            manifestRoute: .native(genericManifest), ghostPlaneAvailability: .admitted
        )
        guard router.destination(for: blocked) == .hostOnly(.isolatedProfileRequired(runtimeClass: .exclusiveStdio)) else {
            throw Failure("exclusive stdio runtime must be rejected from shared profile")
        }
        print("plugin route matrix portable check passed")
    }

    static func manifest(pluginID: String) -> NativeUIManifest {
        .init(
            pluginID: pluginID,
            hostBuildRange: .init(minimumBuildID: OfficialUISpec.Build.id, maximumBuildID: OfficialUISpec.Build.id),
            manifestVersion: NativeUIManifest.currentManifestVersion,
            kind: .settingsForm,
            localeResources: [.init(language: "en", namespace: "fixture", requiredKeys: ["label"])],
            sections: [.init(id: "section", titleKey: "label", fieldIDs: ["field"], groupIDs: [], order: 0)],
            fields: [.init(id: "field", path: ["field"], kind: .text, labelKey: "label", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 0)],
            groups: [], order: 0, secretRoles: [], validations: [], actions: [.save], requiredCapabilities: [],
            integrity: .init(
                algorithm: "sha256",
                digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                sourceCommit: OfficialUISpec.Build.sourceCommit
            )
        )
    }

    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
