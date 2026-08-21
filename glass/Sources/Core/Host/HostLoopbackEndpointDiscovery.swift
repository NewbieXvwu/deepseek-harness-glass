import Foundation

/// Discovery coordinator for an already-running Host. It has no process launch
/// or write RPC ability: callers provide a diagnostics-only `host.describe`
/// probe and receive at most the first exact loopback endpoint that responds.
struct HostLoopbackEndpointDiscovery: Sendable {
    protocol Probe: Sendable {
        func respondsToDescribe(at endpoint: URL) async -> Bool
    }

    func discover(candidates: [URL], using probe: some Probe) async -> URL? {
        for endpoint in canonicalCandidates(candidates) {
            if await probe.respondsToDescribe(at: endpoint) { return endpoint }
        }
        return nil
    }

    func canonicalCandidates(_ candidates: [URL]) -> [URL] {
        var paths = Set<String>()
        return candidates.compactMap { candidate in
            guard candidate.scheme == "http",
                  candidate.host == "127.0.0.1",
                  let port = candidate.port, port > 0,
                  candidate.user == nil, candidate.password == nil,
                  candidate.query == nil, candidate.fragment == nil,
                  candidate.path.isEmpty || candidate.path == "/"
            else { return nil }
            var components = URLComponents()
            components.scheme = "http"
            components.host = "127.0.0.1"
            components.port = port
            components.path = "/"
            guard let normalized = components.url, paths.insert(normalized.absoluteString).inserted else { return nil }
            return normalized
        }
    }
}
