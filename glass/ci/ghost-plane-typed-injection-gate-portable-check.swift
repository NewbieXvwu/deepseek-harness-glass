import Foundation

@main
struct GhostPlaneTypedInjectionGatePortableCheck {
    static func main() throws {
        let policy = try require(GhostPlaneLoopbackPolicy(origin: URL(string: "http://127.0.0.1:7342/")!, pluginIDs: ["dsh-review"]))
        let data = Data("{\"rev\":\"graph-r1\",\"entries\":[{\"id\":\"dsh-review\",\"url\":\"http://127.0.0.1:7342/plugins/dsh-review/client.js?rev=r1\",\"rev\":\"r1\",\"inject\":[\"modules\",\"slots\"],\"immediately\":true,\"external\":[]}]}".utf8)
        let manifest: GhostPlaneModuleManifest
        switch GhostPlaneModuleManifest.admit(data: data, policy: policy, staticModuleSpecifiers: []) {
        case .admitted(let value): manifest = value
        case .rejected(let reason): preconditionFailure("fixture must admit: \(reason)")
        }
        let permit = GhostPlaneModuleActivationGate.ActivationPermit(pluginID: "dsh-review", revision: "r1", graphRevision: "graph-r1")
        let gate = GhostPlaneTypedInjectionGate(manifest: manifest, availableServices: [.modules, .slots])
        precondition(gate.grant(for: permit) == .granted(.init(pluginID: "dsh-review", revision: "r1", graphRevision: "graph-r1", services: [.modules, .slots])))
        precondition(gate.grant(for: .init(pluginID: "dsh-review", revision: "stale", graphRevision: "graph-r1")) == .rejected(.revisionMismatch))
        let unavailable = GhostPlaneTypedInjectionGate(manifest: manifest, availableServices: [.modules])
        precondition(unavailable.grant(for: permit) == .rejected(.unavailableService(.slots)))
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "GhostPlaneTypedInjectionGate", code: 1) }
        return value
    }
}
