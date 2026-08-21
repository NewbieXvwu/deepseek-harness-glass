import XCTest
@testable import GlassCore

final class GhostPlaneTypedInjectionGateTests: XCTestCase {
    func testGrantNeedsMatchingPermitAndAvailableDeclaredServices() throws {
        let manifest = try makeManifest(inject: ["modules", "slots", "modules"])
        let gate = GhostPlaneTypedInjectionGate(manifest: manifest, availableServices: [.modules, .slots])
        let permit = GhostPlaneModuleActivationGate.ActivationPermit(pluginID: "dsh-review", revision: "r1", graphRevision: "graph-r1")
        XCTAssertEqual(gate.grant(for: permit), .granted(.init(pluginID: "dsh-review", revision: "r1", graphRevision: "graph-r1", services: [.modules, .slots])))
        XCTAssertEqual(gate.grant(for: .init(pluginID: "dsh-review", revision: "old", graphRevision: "graph-r1")), .rejected(.revisionMismatch))
    }

    func testUnknownOrUnavailableServiceFailsClosed() throws {
        let unavailable = GhostPlaneTypedInjectionGate(manifest: try makeManifest(inject: ["permission-broker"]), availableServices: [.modules])
        XCTAssertEqual(unavailable.grant(for: permit()), .rejected(.unavailableService(.permissionBroker)))
        let unknown = GhostPlaneTypedInjectionGate(manifest: try makeManifest(inject: ["dangerous"]), availableServices: Set(GhostPlaneTypedInjectionGate.Service.allCases))
        XCTAssertEqual(unknown.grant(for: permit()), .rejected(.unknownService("dangerous")))
    }

    private func permit() -> GhostPlaneModuleActivationGate.ActivationPermit { .init(pluginID: "dsh-review", revision: "r1", graphRevision: "graph-r1") }

    private func makeManifest(inject: [String]) throws -> GhostPlaneModuleManifest {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(origin: URL(string: "http://127.0.0.1:7342/")!, pluginIDs: ["dsh-review"]))
        let encodedInject = inject.map { "\"\($0)\"" }.joined(separator: ",")
        let data = Data("{\"rev\":\"graph-r1\",\"entries\":[{\"id\":\"dsh-review\",\"url\":\"http://127.0.0.1:7342/plugins/dsh-review/client.js?rev=r1\",\"rev\":\"r1\",\"inject\":[\(encodedInject)],\"immediately\":true,\"external\":[]}]}".utf8)
        switch GhostPlaneModuleManifest.admit(data: data, policy: policy, staticModuleSpecifiers: []) {
        case .admitted(let manifest): return manifest
        case .rejected(let reason): throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(reason)"])
        }
    }
}
