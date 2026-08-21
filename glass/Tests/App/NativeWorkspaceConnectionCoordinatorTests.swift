import XCTest

@testable import GlassUI

@MainActor
final class NativeWorkspaceConnectionCoordinatorTests: XCTestCase {
    func testSameWorkspaceSharesSingleInFlightHostCreate() async throws {
        let reached = expectation(description: "one Host create starts")
        let gate = RecoveryGate()
        let coordinator = NativeWorkspaceConnectionCoordinator()
        var calls = 0

        let first = Task {
            try await coordinator.connect(workspaceID: "workspace-a") {
                calls += 1
                reached.fulfill()
                await gate.wait()
                return "host-session-a"
            }
        }
        await fulfillment(of: [reached], timeout: 1)
        let second = Task {
            try await coordinator.connect(workspaceID: "workspace-a") {
                XCTFail("same workspace must share existing Host create")
                return "synthetic-session"
            }
        }
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(calls, 1)

        await gate.open()
        XCTAssertEqual(try await first.value, "host-session-a")
        XCTAssertEqual(try await second.value, "host-session-a")
        XCTAssertEqual(calls, 1)
    }

    func testCancelledOldConnectionCannotClearNewWorkspaceCoalescingTask() async throws {
        let oldReached = expectation(description: "old Host create starts")
        let freshReached = expectation(description: "fresh Host create starts")
        let oldGate = RecoveryGate()
        let freshGate = RecoveryGate()
        let coordinator = NativeWorkspaceConnectionCoordinator()
        var freshCalls = 0

        let old = Task {
            try await coordinator.connect(workspaceID: "workspace-a") {
                oldReached.fulfill()
                await oldGate.wait()
                return "old-session"
            }
        }
        await fulfillment(of: [oldReached], timeout: 1)
        coordinator.cancelAll()

        let fresh = Task {
            try await coordinator.connect(workspaceID: "workspace-a") {
                freshCalls += 1
                freshReached.fulfill()
                await freshGate.wait()
                return "fresh-session"
            }
        }
        await fulfillment(of: [freshReached], timeout: 1)
        await oldGate.open()
        _ = try? await old.value

        let joined = Task {
            try await coordinator.connect(workspaceID: "workspace-a") {
                XCTFail("late old completion must not clear fresh coalescing task")
                return "synthetic-session"
            }
        }
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(freshCalls, 1)

        await freshGate.open()
        XCTAssertEqual(try await fresh.value, "fresh-session")
        XCTAssertEqual(try await joined.value, "fresh-session")
    }
}
