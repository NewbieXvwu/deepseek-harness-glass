import Foundation

/// Profile routing policy for Ghost Plane packages. It intentionally does not
/// mutate `DSH_HOME`: owned Host home remains a Host lifecycle concern, while
/// this value selects whether a plugin can share the web runtime profile.
public struct GhostPlaneProfilePolicy: Equatable, Sendable {
    public enum Selection: Equatable, Sendable {
        case sharedWeb
        case isolated(name: String)
    }

    public enum Runtime: Equatable, Sendable { case declarativeUI, sharedService, exclusiveStdio, tui }
    public enum Decision: Equatable, Sendable {
        case allow(profilePath: String)
        case requiresIsolatedProfile(runtime: Runtime)
        case invalidIsolatedName
    }

    public let dshHome: URL
    public init(dshHome: URL) { self.dshHome = dshHome }

    public func decision(selection: Selection, runtime: Runtime) -> Decision {
        switch selection {
        case .sharedWeb:
            switch runtime {
            case .exclusiveStdio, .tui: return .requiresIsolatedProfile(runtime: runtime)
            case .declarativeUI, .sharedService: return .allow(profilePath: sharedProfile.path)
            }
        case .isolated(let name):
            guard validName(name) else { return .invalidIsolatedName }
            return .allow(profilePath: isolatedProfile(name: name).path)
        }
    }

    public var sharedProfile: URL { dshHome.appendingPathComponent("profiles/web", isDirectory: true) }
    public func isolatedProfile(name: String) -> URL { dshHome.appendingPathComponent("profiles/glass-\(name)", isDirectory: true) }

    private func validName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            switch scalar.value { case 45, 48...57, 65...90, 97...122: true; default: false }
        }
    }
}
