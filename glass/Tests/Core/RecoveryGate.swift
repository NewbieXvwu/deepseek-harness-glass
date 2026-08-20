import Foundation

actor RecoveryGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation in
            if opened {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
