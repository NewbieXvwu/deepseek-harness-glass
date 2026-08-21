import Foundation
import XCTest
@testable import GlassCore
@testable import GlassSpec

final class SwiftAdapterRegistryTests: XCTestCase {
    private let lockedHostBuild = OfficialUISpec.Build.id
    private let integrity = NativeUIManifest.Integrity(
        algorithm: "sha256",
        digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        sourceCommit: OfficialUISpec.Build.sourceCommit
    )

    func testReviewedAdapterRequiresExactHostAndVerifiedMatchingManifest() {
        let registry = SwiftAdapterRegistry()
        let manifest = manifest(pluginID: "settings.shell")
        let route = NativeUIManifestVerifier.route(manifest, hostBuildID: lockedHostBuild, verifiedIntegrity: integrity)

        guard case let .active(adapter) = registry.availability(
            for: "settings.shell",
            hostBuildID: lockedHostBuild,
            manifestRoute: route
        ) else {
            return XCTFail("reviewed adapter must activate only through its verified native manifest")
        }
        XCTAssertEqual(adapter.adapterID, "swift.settings.shell.v1")
        XCTAssertEqual(adapter.fixtureID, "official-settings-shell-r1")

        XCTAssertEqual(
            registry.availability(for: "settings.shell", hostBuildID: "future-host", manifestRoute: route),
            .inactive(.unsupportedHostBuild(expected: lockedHostBuild, actual: "future-host"))
        )
        XCTAssertEqual(
            registry.availability(for: "settings.shell", hostBuildID: lockedHostBuild, manifestRoute: nil),
            .inactive(.manifestNotVerified)
        )
    }

    func testUnknownPluginCannotBorrowKnownAdapterAndInventoryListsAllStates() {
        let registry = SwiftAdapterRegistry()
        XCTAssertEqual(
            registry.availability(for: "third-party.unreviewed", hostBuildID: lockedHostBuild, manifestRoute: nil),
            .inactive(.unregisteredPlugin)
        )

        let shell = manifest(pluginID: "settings.shell")
        let route = NativeUIManifestVerifier.route(shell, hostBuildID: lockedHostBuild, verifiedIntegrity: integrity)
        let inventory = registry.inventory(hostBuildID: lockedHostBuild, manifestRoutes: ["settings.shell": route])

        XCTAssertEqual(inventory.map(\.descriptor.pluginID), ["settings.agent-loop", "settings.shell", "settings.web-search-deepseek"])
        XCTAssertEqual(inventory.first(where: { $0.descriptor.pluginID == "settings.shell" })?.availability, .active(registry.descriptor(for: "settings.shell")!))
        XCTAssertEqual(inventory.first(where: { $0.descriptor.pluginID == "settings.agent-loop" })?.availability, .inactive(.manifestNotVerified))
    }

    private func manifest(pluginID: String) -> NativeUIManifest {
        .init(
            pluginID: pluginID,
            hostBuildRange: .init(minimumBuildID: lockedHostBuild, maximumBuildID: lockedHostBuild),
            manifestVersion: 1,
            kind: .settingsForm,
            localeResources: [.init(language: "en", namespace: "example", requiredKeys: ["title"])],
            sections: [], fields: [], groups: [], order: 0, secretRoles: [], validations: [], actions: [.save], requiredCapabilities: [], integrity: integrity
        )
    }
}
