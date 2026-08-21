import Foundation

/// Local presentation preference for Ghost Plane profile routing. This is not a
/// Host settings descriptor and never changes owned Host `DSH_HOME`; callers
/// decode it first, then ask `GhostPlaneProfilePolicy` for the actual route.
public struct GhostPlaneProfilePreference: Equatable, Sendable {
    public static let storageKey = "ghostPlane.profilePreference.v1"
    public let selection: GhostPlaneProfilePolicy.Selection

    public init(selection: GhostPlaneProfilePolicy.Selection) { self.selection = selection }

    public var storedValue: String {
        switch selection {
        case .sharedWeb: return "shared"
        case .isolated(let name): return "isolated:\(name)"
        }
    }

    /// Malformed/missing persisted values fail closed to the non-exclusive web
    /// profile. The route policy performs its own name validation before any
    /// filesystem path can be produced.
    public static func decode(_ storedValue: String?) -> GhostPlaneProfilePreference {
        guard let storedValue else { return .init(selection: .sharedWeb) }
        if storedValue == "shared" { return .init(selection: .sharedWeb) }
        if storedValue.hasPrefix("isolated:") {
            let name = String(storedValue.dropFirst("isolated:".count))
            return .init(selection: .isolated(name: name))
        }
        return .init(selection: .sharedWeb)
    }
}
