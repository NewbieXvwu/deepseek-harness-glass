import XCTest

final class RecoveryGateTests: XCTestCase {
    func testOpenReleasesAllConcurrentWaiters() async {
        let gate = RecoveryGate()
        let firstReleased = expectation(description: "first waiter exits after gate opens")
        let secondReleased = expectation(description: "second waiter exits after gate opens")
        let first = Task {
            await gate.wait()
            firstReleased.fulfill()
        }
        let second = Task {
            await gate.wait()
            secondReleased.fulfill()
        }

        await gate.open()
        await fulfillment(of: [firstReleased, secondReleased], timeout: 1)
        await first.value
        await second.value
    }

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

    func testOpenIsIdempotentAndLateCancellationCannotDoubleResume() async {
        let gate = RecoveryGate()
        let released = expectation(description: "waiter exits after first open")
        let waiter = Task {
            await gate.wait()
            released.fulfill()
            // A cancellation callback racing a late `open()` must find no
            // table entry and resume nothing a second time.
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        await gate.open()
        await fulfillment(of: [released], timeout: 1)
        await gate.open()
        waiter.cancel()
        await waiter.value

        let trailing = expectation(description: "post-open wait returns immediately")
        let trailingTask = Task {
            await gate.wait()
            trailing.fulfill()
        }
        await fulfillment(of: [trailing], timeout: 1)
        await trailingTask.value
    }
}
