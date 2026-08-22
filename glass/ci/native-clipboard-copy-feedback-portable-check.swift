import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeClipboardCopyFeedbackPortableCheck {
    static func main() throws {
        let idle = NativeClipboardCopyFeedback.State.idle
        guard NativeClipboardCopyFeedback.acceptsActivation(state: idle),
              NativeClipboardCopyFeedback.resolveWrite(state: idle, accepted: true) == .copied,
              NativeClipboardCopyFeedback.resolveExpiry(state: .copied) == .idle else {
            throw CheckFailure(description: "accepted clipboard writes must produce one transient copied state")
        }
        guard NativeClipboardCopyFeedback.resolveWrite(state: idle, accepted: false) == .idle,
              NativeClipboardCopyFeedback.resolveWrite(state: .copied, accepted: true) == .copied,
              !NativeClipboardCopyFeedback.acceptsActivation(state: .copied) else {
            throw CheckFailure(description: "refused or repeated clipboard writes must not claim a new copy")
        }
        print("native clipboard copy feedback portable check passed")
    }
}
