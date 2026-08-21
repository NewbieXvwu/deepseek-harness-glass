import Foundation

@main
struct GhostPlaneModuleActivationGatePortableCheck {
    static func main() throws {
        let policy = try require(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!, pluginIDs: ["dsh-runtime", "dsh-review"]
        ))
        let data = Data("""
        {"rev":"graph-r1","entries":[
          {"id":"dsh-runtime","url":"http://127.0.0.1:7342/plugins/dsh-runtime/client.js?rev=runtime-r1","rev":"runtime-r1","inject":[],"immediately":true,"external":["react"]},
          {"id":"dsh-review","url":"http://127.0.0.1:7342/plugins/dsh-review/client.js?rev=review-r1","rev":"review-r1","inject":[],"immediately":true,"external":["dsh-runtime/client","react"]}
        ]}
        """.utf8)
        let manifest: GhostPlaneModuleManifest
        switch GhostPlaneModuleManifest.admit(data: data, policy: policy, staticModuleSpecifiers: ["react"]) {
        case .admitted(let value): manifest = value
        case .rejected(let reason): preconditionFailure("fixture must admit: \(reason)")
        }
        var gate = GhostPlaneModuleActivationGate(manifest: manifest, staticModuleSpecifiers: ["react"])
        precondition(gate.permitActivation(pluginID: "dsh-review") == .rejected(.bundleNotArrived))
        precondition(gate.admitArrival(pluginID: "dsh-review", revision: "stale") == .rejected(.revisionMismatch))
        precondition(gate.admitArrival(pluginID: "dsh-review", revision: "review-r1") == .admitted)
        precondition(gate.permitActivation(pluginID: "dsh-review") == .rejected(.dependencyNotArrived("dsh-runtime")))
        precondition(gate.admitArrival(pluginID: "dsh-runtime", revision: "runtime-r1") == .admitted)
        precondition(gate.permitActivation(pluginID: "dsh-review") == .permitted(.init(pluginID: "dsh-review", revision: "review-r1", graphRevision: "graph-r1")))
        precondition(gate.permitActivation(pluginID: "dsh-review") == .rejected(.alreadyActivated))
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "GhostPlaneActivationGate", code: 1) }
        return value
    }
}
