import Foundation

/// Admission policy for all Ghost Plane network/navigation decisions. It is a
/// pure Core value so the WebKit delegate can make one deterministic decision
/// without teaching the native shell to trust arbitrary plugin URLs.
public struct GhostPlaneLoopbackPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case allowSkeletonDocument
        case allowPluginResource(pluginID: String)
        case allowPluginCombo(pluginIDs: [String], sourceMap: Bool)
        case deny(Denial)
    }

    public enum Denial: Equatable, Sendable {
        case invalidOrigin
        case unsupportedScheme
        case nonLoopbackHost
        case wrongPort
        case credentialedURL
        case unregisteredPlugin
        case nonPluginPath
        case encodedTraversal
        case malformedCombo
    }

    public let origin: URL
    private let pluginIDs: Set<String>

    public init?(origin: URL, pluginIDs: Set<String>) {
        guard Self.isCanonicalLoopbackOrigin(origin), pluginIDs.allSatisfy(Self.isValidPluginID) else {
            return nil
        }
        self.origin = origin
        self.pluginIDs = pluginIDs
    }

    /// rc.1 serves JavaScript through content-addressed `/plugins/??…&rev=…`
    /// combo URLs. Registered plugin assets may still live below a package root.
    public func decision(for request: URL) -> Decision {
        guard request.scheme?.lowercased() == "http" else { return .deny(.unsupportedScheme) }
        guard request.user == nil, request.password == nil else { return .deny(.credentialedURL) }
        guard request.host?.lowercased() == "127.0.0.1" else { return .deny(.nonLoopbackHost) }
        guard request.port == origin.port else { return .deny(.wrongPort) }
        guard let components = URLComponents(url: request, resolvingAgainstBaseURL: false) else {
            return .deny(.invalidOrigin)
        }
        let encodedPath = components.percentEncodedPath.lowercased()
        guard !encodedPath.contains("%2e"), !encodedPath.contains("%2f"), !encodedPath.contains("%5c") else {
            return .deny(.encodedTraversal)
        }
        if request.path == "/", components.queryItems == nil, components.fragment == nil {
            return .allowSkeletonDocument
        }
        if request.path == "/plugins" || request.path == "/plugins/" {
            return comboDecision(percentEncodedQuery: components.percentEncodedQuery)
        }
        let prefix = "/plugins/"
        guard request.path.hasPrefix(prefix) else { return .deny(.nonPluginPath) }
        let suffix = String(request.path.dropFirst(prefix.count))
        guard let pluginID = pluginIDs
            .filter({ suffix == $0 || suffix.hasPrefix($0 + "/") })
            .max(by: { $0.count < $1.count })
        else { return .deny(.unregisteredPlugin) }
        return .allowPluginResource(pluginID: pluginID)
    }

    public func pluginRootURL(for pluginID: String) -> URL? {
        guard pluginIDs.contains(pluginID) else { return nil }
        return origin.appendingPathComponent("plugins", isDirectory: true).appendingPathComponent(pluginID, isDirectory: true)
    }

    private func comboDecision(percentEncodedQuery: String?) -> Decision {
        guard var query = percentEncodedQuery, query.first == "?" else { return .deny(.nonPluginPath) }
        query.removeFirst()
        let parts = query.components(separatedBy: "&")
        guard parts.count == 2, parts[1].hasPrefix("rev="), parts[1].count > 4 else { return .deny(.malformedCombo) }
        let resources = parts[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !resources.isEmpty, !resources.contains(where: \.isEmpty) else { return .deny(.malformedCombo) }
        let isMap = resources[0].hasSuffix("/client.js.map")
        let suffix = isMap ? "/client.js.map" : "/client.js"
        guard resources.allSatisfy({ $0.hasSuffix(suffix) }) else { return .deny(.malformedCombo) }
        let ids = resources.map { String($0.dropLast(suffix.count)) }
        guard Set(ids).count == ids.count else { return .deny(.malformedCombo) }
        guard ids.allSatisfy(pluginIDs.contains) else { return .deny(.unregisteredPlugin) }
        return .allowPluginCombo(pluginIDs: ids, sourceMap: isMap)
    }

    private static func isCanonicalLoopbackOrigin(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", url.host?.lowercased() == "127.0.0.1", let port = url.port, port > 0,
              url.user == nil, url.password == nil, (url.path.isEmpty || url.path == "/"), url.query == nil, url.fragment == nil
        else { return false }
        return true
    }

    static func isValidPluginID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        func component(_ value: Substring) -> Bool {
            !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 45, 46, 95, 48...57, 65...90, 97...122: true
                default: false
                }
            }
        }
        if id.first == "@" {
            let body = id.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            return body.count == 2 && component(body[0]) && component(body[1])
        }
        return !id.contains("/") && component(Substring(id))
    }
}
