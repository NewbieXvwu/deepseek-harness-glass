import XCTest
@testable import GlassCore

final class GhostPlaneModuleActivationGateTests: XCTestCase {
    func testActivationWaitsForAdmittedDependencyArrival() throws {
        var gate = try makeGate()
        XCTAssertEqual(gate.admitArrival(pluginID: "dsh-runtime", revision: "runtime-r1"), .admitted)
        XCTAssertEqual(gate.permitActivation(pluginID: "dsh-review"), .rejected(.bundleNotArrived))
        XCTAssertEqual(gate.admitArrival(pluginID: "dsh-review", revision: "review-r1"), .admitted)
        XCTAssertEqual(
            gate.permitActivation(pluginID: "dsh-review"),
            .permitted(.init(pluginID: "dsh-review", revision: "review-r1", graphRevision: "graph-r1"))
        )
        XCTAssertEqual(gate.permitActivation(pluginID: "dsh-review"), .rejected(.alreadyActivated))
    }

    func testGateRejectsUnknownStaleAndDuplicateArrivals() throws {
        var gate = try makeGate()
        XCTAssertEqual(gate.admitArrival(pluginID: "unknown", revision: "x"), .rejected(.unknownBundle))
        XCTAssertEqual(gate.admitArrival(pluginID: "dsh-review", revision: "stale"), .rejected(.revisionMismatch))
        XCTAssertEqual(gate.admitArrival(pluginID: "dsh-review", revision: "review-r1"), .admitted)
        XCTAssertEqual(gate.admitArrival(pluginID: "dsh-review", revision: "review-r1"), .rejected(.duplicateArrival))
    }

    private func makeGate() throws -> GhostPlaneModuleActivationGate {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!, pluginIDs: ["dsh-runtime", "dsh-review"]
        ))
        let data = Data("""
        {"rev":"graph-r1","entries":[
          {"id":"dsh-runtime","url":"http://127.0.0.1:7342/plugins/??dsh-runtime/client.js&rev=runtime-r1","rev":"runtime-r1","inject":[],"immediately":true,"external":["react"]},
          {"id":"dsh-review","url":"http://127.0.0.1:7342/plugins/??dsh-review/client.js&rev=review-r1","rev":"review-r1","inject":["dsh-runtime"],"immediately":true,"external":["react"]}
        ],"batches":[
          {"phase":"bootstrap","url":"http://127.0.0.1:7342/plugins/??dsh-runtime/client.js&rev=boot-r1","rev":"boot-r1","entries":["dsh-runtime"]},
          {"phase":"application","url":"http://127.0.0.1:7342/plugins/??dsh-review/client.js&rev=app-r1","rev":"app-r1","entries":["dsh-review"]}
        ]}
        """.utf8)
        let manifest: GhostPlaneModuleManifest
        switch GhostPlaneModuleManifest.admit(data: data, policy: policy, staticModuleSpecifiers: ["react"]) {
        case .admitted(let admitted): manifest = admitted
        case .rejected(let rejection): throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(rejection)"])
        }
        return .init(manifest: manifest, staticModuleSpecifiers: ["react"])
    }
}
