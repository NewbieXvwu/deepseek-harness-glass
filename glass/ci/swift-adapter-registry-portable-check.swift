import Foundation

enum OfficialUISpec {
    enum Build {
        static let id = "dsh-0.1.1-rc.2-official-b150a55"
        static let sourceCommit = "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e"
        static func isCompatible(with hostBuildID: String) -> Bool { hostBuildID == id }
    }
}

@main
struct SwiftAdapterRegistryPortableCheck {
    static func main() throws {
        let integrity = NativeUIManifest.Integrity(
            algorithm: "sha256",
            digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            sourceCommit: OfficialUISpec.Build.sourceCommit
        )
        let manifest = NativeUIManifest(
            pluginID: "settings.shell",
            hostBuildRange: .init(minimumBuildID: OfficialUISpec.Build.id, maximumBuildID: OfficialUISpec.Build.id),
            manifestVersion: 1,
            kind: .settingsForm,
            localeResources: [.init(language: "en", namespace: "example", requiredKeys: ["title"])],
            sections: [], fields: [], groups: [], order: 0, secretRoles: [], validations: [], actions: [.save], requiredCapabilities: [], integrity: integrity
        )
        let verifiedRoute = NativeUIManifestVerifier.route(
            manifest,
            hostBuildID: OfficialUISpec.Build.id,
            verifiedIntegrity: integrity
        )
        let registry = SwiftAdapterRegistry()
        guard case let .active(adapter) = registry.availability(
            for: "settings.shell",
            hostBuildID: OfficialUISpec.Build.id,
            manifestRoute: verifiedRoute
        ), adapter.fixtureID == "official-settings-shell-r1" else {
            throw CheckFailure("verified known adapter must become active")
        }
        guard registry.availability(for: "third-party.plugin", hostBuildID: OfficialUISpec.Build.id, manifestRoute: verifiedRoute) == .inactive(.unregisteredPlugin) else {
            throw CheckFailure("unknown plugin must never inherit a native adapter")
        }
        guard registry.availability(for: "settings.shell", hostBuildID: "unreviewed-host", manifestRoute: verifiedRoute) == .inactive(.unsupportedHostBuild(expected: OfficialUISpec.Build.id, actual: "unreviewed-host")) else {
            throw CheckFailure("host mismatch must deactivate reviewed adapter")
        }
        guard registry.availability(for: "settings.shell", hostBuildID: OfficialUISpec.Build.id, manifestRoute: nil) == .inactive(.manifestNotVerified) else {
            throw CheckFailure("missing verified manifest must deactivate reviewed adapter")
        }
        let inventory = registry.inventory(hostBuildID: OfficialUISpec.Build.id, manifestRoutes: ["settings.shell": verifiedRoute])
        guard inventory.count == 3,
              inventory.first(where: { $0.descriptor.pluginID == "settings.shell" })?.availability == .active(adapter) else {
            throw CheckFailure("inventory must enumerate activation state for every reviewed adapter")
        }
        print("swift adapter registry portable check passed")
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
