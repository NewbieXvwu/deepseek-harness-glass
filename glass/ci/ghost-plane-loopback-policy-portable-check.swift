import Foundation

@main
struct GhostPlaneLoopbackPolicyPortableCheck {
    static func main() throws {
        guard let policy = GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-review-loop", "dsh.open_in_vscode"]
        ) else {
            throw CheckFailure("canonical loopback policy fixture must initialize")
        }
        guard policy.decision(for: URL(string: "http://127.0.0.1:7342/")!) == .allowSkeletonDocument else {
            throw CheckFailure("exact native skeleton origin must be admitted")
        }
        guard policy.decision(for: URL(string: "http://127.0.0.1:7342/plugins/dsh-review-loop/client.js")!) == .allowPluginResource(pluginID: "dsh-review-loop") else {
            throw CheckFailure("registered same-origin plugin resource must be admitted")
        }
        let denied: [(String, GhostPlaneLoopbackPolicy.Denial)] = [
            ("https://127.0.0.1:7342/plugins/dsh-review-loop/client.js", .unsupportedScheme),
            ("file:///tmp/client.js", .unsupportedScheme),
            ("http://example.com/plugins/dsh-review-loop/client.js", .nonLoopbackHost),
            ("http://127.0.0.1:7343/plugins/dsh-review-loop/client.js", .wrongPort),
            ("http://token@127.0.0.1:7342/plugins/dsh-review-loop/client.js", .credentialedURL),
            ("http://127.0.0.1:7342/plugins/unregistered/client.js", .unregisteredPlugin),
            ("http://127.0.0.1:7342/api/host.describe", .nonPluginPath),
            ("http://127.0.0.1:7342/plugins/dsh-review-loop/%2e%2e/client.js", .encodedTraversal),
        ]
        for (raw, reason) in denied {
            guard policy.decision(for: URL(string: raw)!) == .deny(reason) else {
                throw CheckFailure("request \(raw) did not fail closed as \(reason)")
            }
        }
        guard policy.pluginRootURL(for: "dsh-review-loop")?.absoluteString == "http://127.0.0.1:7342/plugins/dsh-review-loop/",
              policy.pluginRootURL(for: "unregistered") == nil else {
            throw CheckFailure("plugin root generation must remain registration-bound")
        }
        guard GhostPlaneLoopbackPolicy(origin: URL(string: "http://localhost:7342/")!, pluginIDs: []) == nil,
              GhostPlaneLoopbackPolicy(origin: URL(string: "http://user@127.0.0.1:7342/")!, pluginIDs: []) == nil,
              GhostPlaneLoopbackPolicy(origin: URL(string: "http://127.0.0.1:0/")!, pluginIDs: []) == nil else {
            throw CheckFailure("non-canonical origins must fail policy construction")
        }
        print("ghost plane loopback policy portable check passed")
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
