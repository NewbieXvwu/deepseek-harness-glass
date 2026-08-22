import Foundation
import XCTest
@testable import GlassCore
@testable import GlassSpec

final class NativeUIManifestTests: XCTestCase {
    private let lockedHostBuild = OfficialUISpec.Build.id
    private let integrity = NativeUIManifest.Integrity(
        algorithm: "sha256",
        digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        sourceCommit: OfficialUISpec.Build.sourceCommit
    )

    func testVerifiedDeclarativeManifestRoutesToNativeRenderer() throws {
        let manifest = makeManifest()
        try NativeUIManifestVerifier.validate(
            manifest,
            hostBuildID: lockedHostBuild,
            verifiedIntegrity: integrity
        )
        XCTAssertEqual(
            NativeUIManifestVerifier.route(
                manifest,
                hostBuildID: lockedHostBuild,
                verifiedIntegrity: integrity
            ),
            .native(manifest)
        )
    }

    func testUnknownVersionAndHostRangeFailClosedToGhostPlane() {
        let unsupportedVersion = makeManifest(manifestVersion: 2)
        XCTAssertEqual(
            NativeUIManifestVerifier.route(
                unsupportedVersion,
                hostBuildID: lockedHostBuild,
                verifiedIntegrity: integrity
            ),
            .ghostPlaneFallback(pluginID: "example.plugin", reason: .unsupportedManifestVersion(2))
        )

        let unreviewedHost = makeManifest(hostBuildRange: .init(minimumBuildID: "future", maximumBuildID: "future"))
        XCTAssertEqual(
            NativeUIManifestVerifier.route(
                unreviewedHost,
                hostBuildID: "future",
                verifiedIntegrity: integrity
            ),
            .ghostPlaneFallback(pluginID: "example.plugin", reason: .unsupportedHostBuild("future"))
        )
    }

    func testUnverifiedOrMalformedIntegrityNeverCreatesNativeForm() {
        let manifest = makeManifest()
        XCTAssertEqual(
            NativeUIManifestVerifier.route(manifest, hostBuildID: lockedHostBuild, verifiedIntegrity: nil),
            .ghostPlaneFallback(pluginID: "example.plugin", reason: .integrityNotVerified)
        )

        let malformed = makeManifest(integrity: .init(
            algorithm: "sha256",
            digest: "not-a-digest",
            sourceCommit: OfficialUISpec.Build.sourceCommit
        ))
        XCTAssertEqual(
            NativeUIManifestVerifier.route(malformed, hostBuildID: lockedHostBuild, verifiedIntegrity: malformed.integrity),
            .ghostPlaneFallback(pluginID: "example.plugin", reason: .malformedIntegrityDigest)
        )
    }

    func testSecretFieldAndUnknownReferencesAreRejectedInsteadOfInterpreted() {
        let secretField = NativeUIManifest.Field(
            id: "apiKey",
            path: ["apiKey"],
            kind: .secret,
            labelKey: "apiKey",
            helpKey: nil,
            options: [],
            validationIDs: [],
            requiredCapabilities: [],
            order: 1
        )
        let secretManifest = makeManifest(fields: [secretField])
        XCTAssertEqual(
            NativeUIManifestVerifier.route(secretManifest, hostBuildID: lockedHostBuild, verifiedIntegrity: integrity),
            .ghostPlaneFallback(pluginID: "example.plugin", reason: .unsafeSecretField("apiKey"))
        )

        let missingFieldManifest = makeManifest(sections: [
            .init(id: "root", titleKey: "title", fieldIDs: ["missing"], groupIDs: [], order: 0),
        ])
        XCTAssertEqual(
            NativeUIManifestVerifier.route(missingFieldManifest, hostBuildID: lockedHostBuild, verifiedIntegrity: integrity),
            .ghostPlaneFallback(pluginID: "example.plugin", reason: .unknownSectionField("root"))
        )
    }

    private func makeManifest(
        manifestVersion: Int = NativeUIManifest.currentManifestVersion,
        hostBuildRange: NativeUIManifest.HostBuildRange? = nil,
        integrity: NativeUIManifest.Integrity? = nil,
        sections: [NativeUIManifest.Section]? = nil,
        fields: [NativeUIManifest.Field]? = nil
    ) -> NativeUIManifest {
        NativeUIManifest(
            pluginID: "example.plugin",
            hostBuildRange: hostBuildRange ?? .init(minimumBuildID: lockedHostBuild, maximumBuildID: lockedHostBuild),
            manifestVersion: manifestVersion,
            kind: .settingsForm,
            localeResources: [
                .init(language: "en", namespace: "example", requiredKeys: ["title", "timeout"]),
                .init(language: "zh", namespace: "example", requiredKeys: ["title", "timeout"]),
            ],
            sections: sections ?? [
                .init(id: "root", titleKey: "title", fieldIDs: ["timeout"], groupIDs: [], order: 0),
            ],
            fields: fields ?? [
                .init(
                    id: "timeout",
                    path: ["timeoutMs"],
                    kind: .number,
                    labelKey: "timeout",
                    helpKey: "timeoutHint",
                    options: [],
                    validationIDs: ["finite"],
                    requiredCapabilities: ["settings.write"],
                    order: 0
                ),
            ],
            groups: [],
            order: 10,
            secretRoles: [
                .init(id: "apiKey", credentialReference: "exampleApiKey", labelKey: "apiKey"),
            ],
            validations: [.init(id: "finite", rule: .finiteNumber)],
            actions: [.save, .discard, .reset],
            requiredCapabilities: ["settings.write"],
            integrity: integrity ?? self.integrity
        )
    }
}
