import Foundation

/// Test-only gate for authority reads. A recovery task can be cancelled by a
/// newer RC8 resync before the test releases its held response, so every
/// waiter must be releasable by `open()`, by its own cancellation, and never
/// resumed twice.
///
/// History: the first version stored a single continuation slot, which a
/// second concurrent `wait()` silently overwrote (leaking the first waiter).
/// A later revision replaced continuations with a 1 ms poll while chasing the
/// `NativeSessionStoreTests` SIGABRT, but lldb traced that abort to a
/// duplicate `-[XCTestExpectation fulfill]` in a test fake - the store's
/// bounded RC8 follow-up authority pull re-fulfilled an already-waited
/// expectation - not to continuation ownership; see
/// `SupersedingGapRecoverySessionAPI`. This version is event-driven again and
/// sound for any number of waiters: actor isolation serializes the
/// check-and-store against every resume, and each continuation is removed
/// from the table before it is resumed exactly once.
actor RecoveryGate {
    private var opened = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func wait() async {
        if opened { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if opened || Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func open() {
        guard !opened else { return }
        opened = true
        let pending = Array(waiters.values)
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    private func cancelWaiter(id: UUID) {
        if let continuation = waiters.removeValue(forKey: id) {
            continuation.resume()
        }
    }
}
