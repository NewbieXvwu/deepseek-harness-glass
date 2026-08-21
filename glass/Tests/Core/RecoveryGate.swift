import Foundation

/// Test-only gate for authority reads. A recovery task can be cancelled by a
/// newer RC8 resync before the test releases its held response, so a waiter
/// must be resumed on cancellation as well as on `open()`. The UUID fences a
/// late cancellation callback from clearing a newer waiter.
actor RecoveryGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    private var opened = false
    private var waiter: Waiter?

    func wait() async {
        guard !opened else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if opened || Task.isCancelled {
                    continuation.resume()
                } else {
                    waiter = .init(id: id, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func open() {
        guard !opened else { return }
        opened = true
        let pending = waiter
        waiter = nil
        pending?.continuation.resume()
    }

    private func cancelWaiter(id: UUID) {
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        waiter.continuation.resume()
    }
}
