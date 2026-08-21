import XCTest

@testable import GlassCore
@testable import GlassSpec

final class PluginRouteMatrixTests: XCTestCase {
    private let hostBuild = OfficialUISpec.Build.id

    func testReviewedAdapterOutranksGenericNativeManifest() {
        let manifest = makeManifest(pluginID: "settings.shell")
        let request = PluginRouteMatrix.Request(
            pluginID: "settings.shell",
            hostBuildID: hostBuild,
            profile: .sharedWeb,
            runtimeClass: .declarativeUI,
            manifestRoute: .native(manifest),
            ghostPlaneAvailability: .admitted
        )

        XCTAssertEqual(
            PluginRouteMatrix().destination(for: request),
            .swiftAdapter(.init(
                adapterID: "swift.settings.shell.v1",
                pluginID: "settings.shell",
                minimumHostBuildID: hostBuild,
                fixtureID: "official-settings-shell-r1",
                renderer: .reviewedBuiltinCard
            ))
        )
    }

    func testVerifiedGenericManifestPrecedesGhostPlane() {
        let manifest = makeManifest(pluginID: "example.plugin")
        let request = PluginRouteMatrix.Request(
            pluginID: "example.plugin",
            hostBuildID: hostBuild,
            profile: .sharedWeb,
            runtimeClass: .declarativeUI,
            manifestRoute: .native(manifest),
            ghostPlaneAvailability: .admitted
        )

        XCTAssertEqual(PluginRouteMatrix().destination(for: request), .nativeManifest(manifest))
    }

    func testUnknownOrInvalidManifestFallsBackOnlyWhenGhostPlaneIsAdmitted() {
        let fallback = NativeUIManifestRoute.ghostPlaneFallback(pluginID: "example.plugin", reason: .integrityNotVerified)
        let admitted = PluginRouteMatrix.Request(
            pluginID: "example.plugin",
            hostBuildID: hostBuild,
            profile: .sharedWeb,
            runtimeClass: .sharedService,
            manifestRoute: fallback,
            ghostPlaneAvailability: .admitted
        )
        XCTAssertEqual(PluginRouteMatrix().destination(for: admitted), .ghostPlane(pluginID: "example.plugin"))

        let unavailable = PluginRouteMatrix.Request(
            pluginID: "example.plugin",
            hostBuildID: hostBuild,
            profile: .sharedWeb,
            runtimeClass: .sharedService,
            manifestRoute: fallback,
            ghostPlaneAvailability: .unavailable
        )
        XCTAssertEqual(PluginRouteMatrix().destination(for: unavailable), .hostOnly(.ghostPlaneUnavailable))
    }

    func testSharedWebProfileRejectsStdioAndTUIBeforeAnyRenderRoute() {
        for runtimeClass in [PluginRouteMatrix.RuntimeClass.exclusiveStdio, .tui] {
            let request = PluginRouteMatrix.Request(
                pluginID: "settings.shell",
                hostBuildID: hostBuild,
                profile: .sharedWeb,
                runtimeClass: runtimeClass,
                manifestRoute: .native(makeManifest(pluginID: "settings.shell")),
                ghostPlaneAvailability: .admitted
            )
            XCTAssertEqual(
                PluginRouteMatrix().destination(for: request),
                .hostOnly(.isolatedProfileRequired(runtimeClass: runtimeClass))
            )
        }
    }

    func testManifestIdentityMismatchNeverRoutesAnotherPluginsNativeSurface() {
        let request = PluginRouteMatrix.Request(
            pluginID: "requested.plugin",
            hostBuildID: hostBuild,
            profile: .isolated(name: "tui-run"),
            runtimeClass: .tui,
            manifestRoute: .native(makeManifest(pluginID: "other.plugin")),
            ghostPlaneAvailability: .admitted
        )
        XCTAssertEqual(
            PluginRouteMatrix().destination(for: request),
            .hostOnly(.manifestPluginMismatch(expected: "requested.plugin", actual: "other.plugin"))
        )
    }

    private func makeManifest(pluginID: String) -> NativeUIManifest {
        .init(
            pluginID: pluginID,
            hostBuildRange: .init(minimumBuildID: hostBuild, maximumBuildID: hostBuild),
            manifestVersion: NativeUIManifest.currentManifestVersion,
            kind: .settingsForm,
            localeResources: [.init(language: "en", namespace: "fixture", requiredKeys: ["label"])],
            sections: [.init(id: "section", titleKey: "label", fieldIDs: ["field"], groupIDs: [], order: 0)],
            fields: [.init(id: "field", path: ["field"], kind: .text, labelKey: "label", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 0)],
            groups: [],
            order: 0,
            secretRoles: [],
            validations: [],
            actions: [.save],
            requiredCapabilities: [],
            integrity: .init(
                algorithm: "sha256",
                digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                sourceCommit: OfficialUISpec.Build.sourceCommit
            )
        )
    }
}
