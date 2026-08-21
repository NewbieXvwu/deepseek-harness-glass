import Foundation

@main
struct GhostPlaneModuleManifestPortableCheck {
    static func main() throws {
        let policy = GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-a", "dsh-b"]
        )!
        let valid = """
        {"rev":"graph-r1","entries":[
          {"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":true,"external":[]},
          {"id":"dsh-b","url":"http://127.0.0.1:7342/plugins/dsh-b/client.js?rev=b-r1","rev":"b-r1","inject":["dsh-a"],"immediately":false,"external":["dsh-a/client","@deepseek-ai/dsh-client-runtime/client"]}
        ]}
        """.data(using: .utf8)!
        guard case let .admitted(manifest) = GhostPlaneModuleManifest.admit(
            data: valid,
            policy: policy,
            staticModuleSpecifiers: ["@deepseek-ai/dsh-client-runtime/client"]
        ), manifest.entries.map(\.id) == ["dsh-a", "dsh-b"] else {
            throw CheckFailure("ordered registered loopback graph must admit")
        }
        let cases: [(String, GhostPlaneModuleManifest.Reason)] = [
            (#"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=wrong","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#, .invalidClientBundlePath),
            (#"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"https://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#, .resourceDenied(.unsupportedScheme)),
            (#"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-b/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#, .resourceIDMismatch),
            (#"{"rev":"graph-r1","entries":[{"id":"dsh-b","url":"http://127.0.0.1:7342/plugins/dsh-b/client.js?rev=b-r1","rev":"b-r1","inject":[],"immediately":false,"external":["dsh-a"]},{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#, .dependencyAfterConsumer),
            (#"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":["unknown"]}]}"#, .unknownExternalSpecifier),
        ]
        for (json, expected) in cases {
            let result = GhostPlaneModuleManifest.admit(
                data: json.data(using: .utf8)!, policy: policy, staticModuleSpecifiers: []
            )
            guard result == .rejected(expected) else {
                throw CheckFailure("manifest negative expected \(expected), got \(result)")
            }
        }
        print("ghost plane module manifest portable check passed")
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
