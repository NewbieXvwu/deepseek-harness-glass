import Foundation

/// One process-scoped launch URL printed by `dsh web`.
///
/// The query token deliberately stays inside `launchURL`; callers never receive
/// it as a long-lived standalone field.
struct HostLaunchDescriptor: Sendable, Equatable {
    let launchURL: URL
    let cleanBaseURL: URL

    init(url: URL) throws {
        guard url.scheme == "http",
              url.host == "127.0.0.1",
              let port = url.port,
              (1...65_535).contains(port),
              url.user == nil,
              url.password == nil,
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
