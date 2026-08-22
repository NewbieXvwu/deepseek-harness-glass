import Foundation

/// Foundation-only state reducer for rc.2's `useCopyFeedback` interaction.
/// Clipboard I/O remains platform-owned; this type makes the success/refusal and
/// one-second feedback transition testable without claiming a pasteboard write.
public enum NativeClipboardCopyFeedback: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case copied
    }

    /// rc.2 ignores repeat activations while the success feedback is visible.
    public static func acceptsActivation(state: State) -> Bool {
        state == .idle
    }

    /// A rejected clipboard write leaves the state unchanged. An accepted write
    /// enters `copied` only when the control was idle.
    public static func resolveWrite(state: State, accepted: Bool) -> State {
        guard acceptsActivation(state: state), accepted else { return state }
        return .copied
    }

    /// The caller schedules this exactly one second after a successful write.
    public static func resolveExpiry(state: State) -> State {
        guard state == .copied else { return state }
        return .idle
    }
}
