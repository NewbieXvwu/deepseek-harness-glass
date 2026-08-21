import XCTest
@testable import GlassCore

final class GhostPlaneModuleQueueLifecycleTests: XCTestCase {
    func testQueueDrainsInPermitOrderThenAcceptsLiveFactories() {
        var lifecycle = GhostPlaneModuleQueueLifecycle()
        XCTAssertSuccess(lifecycle.recordAdmittedFactory(permit("runtime")))
        XCTAssertSuccess(lifecycle.recordAdmittedFactory(permit("review")))
        XCTAssertEqual(lifecycle.switchToLive(), .success(["runtime", "review"]))
        XCTAssertTrue(lifecycle.containsLiveFactory(pluginID: "runtime"))
        XCTAssertSuccess(lifecycle.recordAdmittedFactory(permit("later")))
        XCTAssertTrue(lifecycle.containsLiveFactory(pluginID: "later"))
    }

    func testLifecycleRejectsDuplicateAndSecondLiveTransition() {
        var lifecycle = GhostPlaneModuleQueueLifecycle()
        XCTAssertSuccess(lifecycle.recordAdmittedFactory(permit("review")))
        XCTAssertFailure(lifecycle.recordAdmittedFactory(permit("review")), .duplicateFactory)
        _ = lifecycle.switchToLive()
        XCTAssertEqual(lifecycle.switchToLive(), .failure(.alreadyLive))
    }

    private func XCTAssertSuccess(_ result: Result<Void, GhostPlaneModuleQueueLifecycle.Rejection>, file: StaticString = #filePath, line: UInt = #line) {
        guard case .success = result else { return XCTFail("expected success", file: file, line: line) }
    }

    private func XCTAssertFailure(_ result: Result<Void, GhostPlaneModuleQueueLifecycle.Rejection>, _ expected: GhostPlaneModuleQueueLifecycle.Rejection, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let actual) = result else { return XCTFail("expected failure", file: file, line: line) }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func permit(_ id: String) -> GhostPlaneModuleActivationGate.ActivationPermit {
        .init(pluginID: id, revision: "r1", graphRevision: "graph")
    }
}
