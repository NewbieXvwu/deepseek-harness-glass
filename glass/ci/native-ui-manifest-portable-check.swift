import Foundation

/// Minimal locked-spec seam for compiling the Core-only manifest verifier on
/// Linux. The production target receives the generated OfficialUISpec build.
enum OfficialUISpec {
    enum Build {
        static let id = "dsh-0.1.1-rc.1-official-528c682e"
        static let sourceCommit = "528c682e061696f5a160f363f236ecbf53cbd006"

        static func isCompatible(with hostBuildID: String) -> Bool {
            hostBuildID == id
        }
    }
}

@main
struct NativeUIManifestPortableCheck {
    static func main() throws {
        let integrity = NativeUIManifest.Integrity(
            algorithm: "sha256",
            digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            sourceCommit: OfficialUISpec.Build.sourceCommit
        )
        let manifest = NativeUIManifest(
            pluginID: "example.plugin",
            hostBuildRange: .init(
                minimumBuildID: OfficialUISpec.Build.id,
                maximumBuildID: OfficialUISpec.Build.id
            ),
            manifestVersion: NativeUIManifest.currentManifestVersion,
            kind: .settingsForm,
            localeResources: [
                .init(language: "en", namespace: "example", requiredKeys: ["title"]),
                .init(language: "zh", namespace: "example", requiredKeys: ["title"]),
            ],
            sections: [.init(id: "root", titleKey: "title", fieldIDs: ["timeout"], groupIDs: [], order: 0)],
            fields: [
                .init(
                    id: "timeout",
                    path: ["timeoutMs"],
                    kind: .number,
                    labelKey: "timeout",
                    helpKey: nil,
                    options: [],
                    validationIDs: ["finite"],
                    requiredCapabilities: ["settings.write"],
                    order: 0
                ),
            ],
            groups: [],
            order: 0,
            secretRoles: [.init(id: "apiKey", credentialReference: "exampleApiKey", labelKey: "apiKey")],
            validations: [.init(id: "finite", rule: .finiteNumber)],
            actions: [.save],
            requiredCapabilities: ["settings.write"],
            integrity: integrity
        )

        try NativeUIManifestVerifier.validate(
            manifest,
            hostBuildID: OfficialUISpec.Build.id,
            verifiedIntegrity: integrity
        )
        guard NativeUIManifestVerifier.route(
            manifest,
            hostBuildID: OfficialUISpec.Build.id,
            verifiedIntegrity: nil
        ) == .ghostPlaneFallback(pluginID: "example.plugin", reason: .integrityNotVerified) else {
            throw CheckFailure("unverified manifest must fail closed to Ghost Plane")
        }

        let secretField = NativeUIManifest.Field(
            id: "forbidden",
            path: ["secret"],
            kind: .secret,
            labelKey: "secret",
            helpKey: nil,
            options: [],
            validationIDs: [],
            requiredCapabilities: [],
            order: 1
        )
        var invalid = manifest
        invalid = NativeUIManifest(
            pluginID: invalid.pluginID,
            hostBuildRange: invalid.hostBuildRange,
            manifestVersion: invalid.manifestVersion,
            kind: invalid.kind,
            localeResources: invalid.localeResources,
            sections: [.init(id: "root", titleKey: "title", fieldIDs: ["forbidden"], groupIDs: [], order: 0)],
            fields: [secretField],
            groups: invalid.groups,
            order: invalid.order,
            secretRoles: invalid.secretRoles,
            validations: invalid.validations,
            actions: invalid.actions,
            requiredCapabilities: invalid.requiredCapabilities,
            integrity: invalid.integrity
        )
        guard NativeUIManifestVerifier.route(
            invalid,
            hostBuildID: OfficialUISpec.Build.id,
            verifiedIntegrity: integrity
        ) == .ghostPlaneFallback(pluginID: "example.plugin", reason: .unsafeSecretField("forbidden")) else {
            throw CheckFailure("secret field must never enter a native schema form")
        }

        print("native UI manifest portable check passed")
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
