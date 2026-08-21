import Foundation

/// Test-only gate for authority reads. A recovery task can be cancelled by a
/// newer RC8 resync before the test releases its held response. This deliberately
/// avoids storing a `CheckedContinuation`: macOS can race task cancellation with
/// the test's late `open()` and allocator-abort when a cancelled continuation is
/// resumed from a separate task. The gate is only test infrastructure, so a
/// 1ms cancellable cooperative poll is preferable to unsound continuation
/// ownership; it has one actor-owned state fact and no resume operation.
actor RecoveryGate {
    private var opened = false

    func wait() async {
        while !opened && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func open() {
        opened = true
    }
}
