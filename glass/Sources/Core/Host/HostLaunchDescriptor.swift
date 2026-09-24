import Foundation

extension URL {
    /// The minimum Host boundary shared by announcement parsing, launch
    /// descriptors and loopback downloads: plain `http` on `127.0.0.1` with a
    /// real port and no embedded credentials.
    var isCanonicalLoopbackHTTP: Bool {
        scheme == "http"
            && host == "127.0.0.1"
            && user == nil
            && password == nil
            && (port ?? 0) > 0
    }
}

/// One process-scoped launch URL printed by `dsh web`.
///
/// The query token deliberately stays inside `launchURL`; callers never receive
/// it as a long-lived standalone field.
struct HostLaunchDescriptor: Sendable, Equatable {
    let launchURL: URL
    let cleanBaseURL: URL

    init(url: URL) throws {
        guard url.isCanonicalLoopbackHTTP,
              let port = url.port,
              port <= 65_535,
              url.path == "/",
              url.fragment == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw HostLaunchDescriptorError.invalidURL
        }
        guard let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "token",
              let token = queryItems[0].value,
              !token.isEmpty
        else {
            throw HostLaunchDescriptorError.missingProcessToken
        }
        components.query = nil
        guard let cleanBaseURL = components.url else {
            throw HostLaunchDescriptorError.invalidURL
        }
        self.launchURL = url
        self.cleanBaseURL = cleanBaseURL
    }
}

enum HostLaunchDescriptorError: Error, Sendable, Equatable {
    case invalidURL
    case missingProcessToken
}
