import XCTest

final class RecoveryGateTests: XCTestCase {
    func testCancellationReleasesStaleWaiterWithoutBlockingFreshWaiter() async {
        let gate = RecoveryGate()
        let staleReleased = expectation(description: "cancelled stale waiter exits")
        let stale = Task {
            await gate.wait()
            staleReleased.fulfill()
        }

        stale.cancel()
        await fulfillment(of: [staleReleased], timeout: 1)
        await stale.value

        let freshReleased = expectation(description: "fresh waiter exits after gate opens")
        let fresh = Task {
            await gate.wait()
            freshReleased.fulfill()
        }
        await gate.open()
        await fulfillment(of: [freshReleased], timeout: 1)
        await fresh.value
    }
}
