import Foundation

/// One process-scoped launch URL printed by `dsh web`.
///
/// The query token deliberately stays inside `launchURL`; callers never receive
/// it as a long-lived standalone field.
struct HostLaunchDescriptor: Sendable, Equatable {
    let launchURL: URL

    init(url: URL) throws {
        guard url.scheme == "http",
              url.host == "127.0.0.1",
              url.port != nil,
              url.user == nil,
              url.password == nil,
              url.path == "/",
              url.fragment == nil
        else {
            throw HostLaunchDescriptorError.invalidURL
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "token",
              let token = queryItems[0].value,
              !token.isEmpty
        else {
            throw HostLaunchDescriptorError.missingProcessToken
        }
        self.launchURL = url
    }

    var cleanBaseURL: URL {
        var components = URLComponents(url: launchURL, resolvingAgainstBaseURL: false)!
        components.query = nil
        components.fragment = nil
        return components.url!
    }
}

enum HostLaunchDescriptorError: Error, Sendable, Equatable {
    case invalidURL
    case missingProcessToken
}
