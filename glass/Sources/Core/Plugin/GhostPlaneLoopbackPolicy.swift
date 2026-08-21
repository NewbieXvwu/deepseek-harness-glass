import Foundation

/// Admission policy for all Ghost Plane network/navigation decisions. It is a
/// pure Core value so the WebKit delegate can make one deterministic decision
/// without teaching the native shell to trust arbitrary plugin URLs.
struct GhostPlaneLoopbackPolicy: Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        case allowPluginResource(pluginID: String)
        case deny(Denial)
    }

    enum Denial: Equatable, Sendable {
        case invalidOrigin
        case unsupportedScheme
        case nonLoopbackHost
        case wrongPort
        case credentialedURL
        case unregisteredPlugin
        case nonPluginPath
        case encodedTraversal
    }

    let origin: URL
    private let pluginIDs: Set<String>

    init?(origin: URL, pluginIDs: Set<String>) {
        guard Self.isCanonicalLoopbackOrigin(origin), pluginIDs.allSatisfy(Self.isValidPluginID) else {
            return nil
        }
        self.origin = origin
        self.pluginIDs = pluginIDs
    }

    /// The only local document/resource paths admitted after the native host
    /// has loaded its own skeleton HTML. Every admitted resource belongs below
    /// `/plugins/<registered-id>/`; Core/App assets are not exposed to plugins.
    func decision(for request: URL) -> Decision {
        guard request.scheme?.lowercased() == "http" else { return .deny(.unsupportedScheme) }
        guard request.user == nil, request.password == nil else { return .deny(.credentialedURL) }
        guard request.host?.lowercased() == "127.0.0.1" else { return .deny(.nonLoopbackHost) }
        guard request.port == origin.port else { return .deny(.wrongPort) }
        guard let urlComponents = URLComponents(url: request, resolvingAgainstBaseURL: false) else {
            return .deny(.invalidOrigin)
        }
        let encodedPath = urlComponents.percentEncodedPath.lowercased()
        guard !encodedPath.contains("%2e"), !encodedPath.contains("%2f"), !encodedPath.contains("%5c") else {
            return .deny(.encodedTraversal)
        }
        let pathComponents = request.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard pathComponents.count >= 3, pathComponents[0] == "plugins" else { return .deny(.nonPluginPath) }
        let pluginID = pathComponents[1]
        guard pluginIDs.contains(pluginID) else { return .deny(.unregisteredPlugin) }
        return .allowPluginResource(pluginID: pluginID)
    }

    func pluginRootURL(for pluginID: String) -> URL? {
        guard pluginIDs.contains(pluginID) else { return nil }
        return origin
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
    }

    private static func isCanonicalLoopbackOrigin(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http",
              url.host?.lowercased() == "127.0.0.1",
              let port = url.port,
              port > 0,
              url.user == nil,
              url.password == nil,
              (url.path.isEmpty || url.path == "/"),
              url.query == nil,
              url.fragment == nil
        else { return false }
        return true
    }

    private static func isValidPluginID(_ pluginID: String) -> Bool {
        guard !pluginID.isEmpty, pluginID.count <= 128 else { return false }
        return pluginID.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 95, 48...57, 65...90, 97...122: true // - . _ ASCII alphanumerics
            default: false
            }
        }
    }
}
