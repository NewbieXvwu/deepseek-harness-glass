import Foundation

/// A reviewed native fast-path declaration. It is metadata only: renderers are
/// selected by the UI layer after the registry has admitted an exact plugin ID,
/// an audited Host build and an integrity-verified manifest route.
struct SwiftAdapterDescriptor: Codable, Equatable, Sendable, Identifiable {
    enum Renderer: String, Codable, CaseIterable, Sendable {
        case nativeSchemaForm
        case reviewedBuiltinCard
    }

    let adapterID: String
    let pluginID: String
    let minimumHostBuildID: String
    let fixtureID: String
    let renderer: Renderer

    var id: String { adapterID }
}

enum SwiftAdapterAvailability: Equatable, Sendable {
    case active(SwiftAdapterDescriptor)
    case inactive(SwiftAdapterInactiveReason)
}

enum SwiftAdapterInactiveReason: Equatable, Sendable {
    case unregisteredPlugin
    case unsupportedHostBuild(expected: String, actual: String)
    case manifestNotVerified
}

struct SwiftAdapterInventoryRow: Equatable, Sendable, Identifiable {
    let descriptor: SwiftAdapterDescriptor
    let availability: SwiftAdapterAvailability

    var id: String { descriptor.adapterID }
}

/// Closed registry of reviewed adapters. A plugin cannot register Swift code at
/// runtime: additions are source changes with fixture and Host-build metadata.
struct SwiftAdapterRegistry: Sendable {
    let adapters: [SwiftAdapterDescriptor]

    init(adapters: [SwiftAdapterDescriptor] = SwiftAdapterRegistry.reviewedAdapters) {
        precondition(Set(adapters.map(\.adapterID)).count == adapters.count, "Swift adapter IDs must be unique")
        precondition(Set(adapters.map(\.pluginID)).count == adapters.count, "Swift adapter plugin IDs must be unique")
        self.adapters = adapters.sorted { $0.adapterID < $1.adapterID }
    }

    /// Initial catalogue intentionally contains only the three built-in settings
    /// surfaces whose Host namespace/field contracts are locked in the official
    /// ui-settings-plugins package. These identifiers are local adapter plugin
    /// identities, never inferred from arbitrary Cordis package names.
    static let reviewedAdapters: [SwiftAdapterDescriptor] = [
        .init(
            adapterID: "swift.settings.agent-loop.v1",
            pluginID: "settings.agent-loop",
            minimumHostBuildID: "dsh-0.1.1-rc.1-official-528c682e",
            fixtureID: "official-settings-agent-loop-r1",
            renderer: .reviewedBuiltinCard
        ),
        .init(
            adapterID: "swift.settings.shell.v1",
            pluginID: "settings.shell",
            minimumHostBuildID: "dsh-0.1.1-rc.1-official-528c682e",
            fixtureID: "official-settings-shell-r1",
            renderer: .reviewedBuiltinCard
        ),
        .init(
            adapterID: "swift.settings.web-search-deepseek.v1",
            pluginID: "settings.web-search-deepseek",
            minimumHostBuildID: "dsh-0.1.1-rc.1-official-528c682e",
            fixtureID: "official-settings-web-search-r1",
            renderer: .reviewedBuiltinCard
        ),
    ]

    func descriptor(for pluginID: String) -> SwiftAdapterDescriptor? {
        adapters.first(where: { $0.pluginID == pluginID })
    }

    func availability(
        for pluginID: String,
        hostBuildID: String,
        manifestRoute: NativeUIManifestRoute?
    ) -> SwiftAdapterAvailability {
        guard let descriptor = descriptor(for: pluginID) else {
            return .inactive(.unregisteredPlugin)
        }
        guard descriptor.minimumHostBuildID == hostBuildID else {
            return .inactive(.unsupportedHostBuild(expected: descriptor.minimumHostBuildID, actual: hostBuildID))
        }
        guard case let .native(manifest)? = manifestRoute, manifest.pluginID == pluginID else {
            return .inactive(.manifestNotVerified)
        }
        return .active(descriptor)
    }

    /// A diagnostics-ready view for every registered fast path. The caller
    /// supplies already verified routes; this method never reinterprets plugin
    /// JSON nor transforms an inactive adapter into a fallback renderer.
    func inventory(
        hostBuildID: String,
        manifestRoutes: [String: NativeUIManifestRoute]
    ) -> [SwiftAdapterInventoryRow] {
        adapters.map { descriptor in
            .init(
                descriptor: descriptor,
                availability: availability(
                    for: descriptor.pluginID,
                    hostBuildID: hostBuildID,
                    manifestRoute: manifestRoutes[descriptor.pluginID]
                )
            )
        }
    }
}
