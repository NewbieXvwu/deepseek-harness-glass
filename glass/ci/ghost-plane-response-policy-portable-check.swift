import Foundation

@main
struct GhostPlaneResponsePolicyPortableCheck {
    static func main() throws {
        let loopback = try require(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!, pluginIDs: ["dsh-review"]
        ))
        let policy = GhostPlaneResponsePolicy(loopback: loopback)
        let skeleton = URL(string: "http://127.0.0.1:7342/")!
        precondition(policy.decision(requestURL: skeleton, responseURL: skeleton, statusCode: 200, mimeType: "text/html; charset=utf-8") == .allowSkeletonDocument)
        let script = URL(string: "http://127.0.0.1:7342/plugins/dsh-review/client.js?rev=r1")!
        precondition(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "application/javascript") == .allowPluginResource(pluginID: "dsh-review"))
        let redirected = URL(string: "http://127.0.0.1:7342/plugins/dsh-review/other.js?rev=r1")!
        precondition(policy.decision(requestURL: script, responseURL: redirected, statusCode: 200, mimeType: "application/javascript") == .deny(.redirect))
        precondition(policy.decision(requestURL: script, responseURL: script, statusCode: 302, mimeType: "application/javascript") == .deny(.nonSuccessStatus))
        precondition(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "text/html") == .deny(.unexpectedMIMEType))
        precondition(policy.decision(requestURL: script, responseURL: script, statusCode: 200, mimeType: "text/css") == .deny(.pathMIMEMismatch))
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "GhostPlaneResponsePolicy", code: 1) }
        return value
    }
}
