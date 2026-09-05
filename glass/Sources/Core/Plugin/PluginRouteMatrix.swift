import Foundation

/// Route selection for modules already present in the rc.1 `dsh web` profile.
/// It never invents a second profile, loads a module, starts a process, or grants
/// a capability; the selected target must perform its own admission.
struct PluginRouteMatrix: Sendable {
    enum RuntimeClass: Equatable, Sendable {
        case declarativeUI
        case sharedService
        case exclusiveStdio
        case tui

        var isWebCompatible: Bool {
            switch self {
            case .declarativeUI, .sharedService: true
            case .exclusiveStdio, .tui: false
            }
        }
    }

    enum GhostPlaneAvailability: Equatable, Sendable {
        case admitted
        case unavailable
    }

    struct Request: Equatable, Sendable {
        let pluginID: String
        let hostBuildID: String
        let runtimeClass: RuntimeClass
        /// Already verified route from `NativeUIManifestVerifier`; raw JSON is
        /// intentionally not accepted at this layer.
        let manifestRoute: NativeUIManifestRoute?
        let ghostPlaneAvailability: GhostPlaneAvailability

        init(
            pluginID: String,
            hostBuildID: String,
            runtimeClass: RuntimeClass,
            manifestRoute: NativeUIManifestRoute?,
            ghostPlaneAvailability: GhostPlaneAvailability
        ) {
            self.pluginID = pluginID
            self.hostBuildID = hostBuildID
            self.runtimeClass = runtimeClass
            self.manifestRoute = manifestRoute
            self.ghostPlaneAvailability = ghostPlaneAvailability
        }
    }

    enum Destination: Equatable, Sendable {
        case swiftAdapter(SwiftAdapterDescriptor)
        case nativeManifest(NativeUIManifest)
        case ghostPlane(pluginID: String)
        case hostOnly(HostOnlyReason)
    }

    enum HostOnlyReason: Equatable, Sendable {
        case independentRuntimeRequired(runtimeClass: RuntimeClass)
        case manifestPluginMismatch(expected: String, actual: String)
        case ghostPlaneUnavailable
    }

    let adapterRegistry: SwiftAdapterRegistry

    init(adapterRegistry: SwiftAdapterRegistry = .init()) {
        self.adapterRegistry = adapterRegistry
    }

    /// Priority is fixed and fail-closed: a registered adapter gets the native
    /// fast path only after exact build/manifest admission; otherwise a verified
    /// generic native manifest may render. Ghost Plane is only a later route.
    func destination(for request: Request) -> Destination {
        // The owned Host is the rc.1 `web` profile. Stdio-owning and TUI
        // runtimes are separate applications and cannot be made web-compatible
        // by a Glass-local preference.
        guard request.runtimeClass.isWebCompatible else {
            return .hostOnly(.independentRuntimeRequired(runtimeClass: request.runtimeClass))
        }
        if case let .active(adapter) = adapterRegistry.availability(
            for: request.pluginID,
            hostBuildID: request.hostBuildID,
            manifestRoute: request.manifestRoute
        ) {
            return .swiftAdapter(adapter)
        }
        if case let .native(manifest)? = request.manifestRoute {
            guard manifest.pluginID == request.pluginID else {
                return .hostOnly(.manifestPluginMismatch(expected: request.pluginID, actual: manifest.pluginID))
            }
            return .nativeManifest(manifest)
        }
        switch request.ghostPlaneAvailability {
        case .admitted:
            return .ghostPlane(pluginID: request.pluginID)
        case .unavailable:
            return .hostOnly(.ghostPlaneUnavailable)
        }
    }
}
