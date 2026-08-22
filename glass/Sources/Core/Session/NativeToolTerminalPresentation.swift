import Foundation

/// A typed subset of the Host-authoritative `ToolEventView` terminal card.
///
/// The Core transport adapter is the only layer that turns wire JSON into this
/// value. Unknown cards never become this type, so UI callers cannot mistake an
/// arbitrary plugin payload for a terminal transcript.
public struct NativeToolTerminalView: Equatable, Sendable {
    public let card: String
    public let title: String?
    public let description: String?
    public let cwd: String?
    public let output: String?
    public let exitCode: Int?
    public let signal: String?

    public init(
        card: String,
        title: String? = nil,
        description: String? = nil,
        cwd: String? = nil,
        output: String? = nil,
        exitCode: Int? = nil,
        signal: String? = nil
    ) {
        self.card = card
        self.title = title
        self.description = description
        self.cwd = cwd
        self.output = output
        self.exitCode = exitCode
        self.signal = signal
    }
}

/// Foundation-only equivalent of rc.2 `terminalCardModel` selection. It accepts
/// already-admitted call/result views rather than decoding raw wire dictionaries:
/// Core retains the event target and owns the fail-closed adapter, while every
/// renderer can share the same deterministic terminal-or-generic decision.
public struct NativeTerminalCardPresentation: Equatable, Sendable {
    public let command: String
    public let description: String?
    public let cwd: String?
    public let output: String?
    public let exitCode: Int?
    public let signal: String?
    public let running: Bool

    /// Mirrors `terminalCardModel(block)`: a running call requires a terminal
    /// call view; a settled result requires a terminal result view. In
    /// particular, a terminal call followed by a generic result stays generic,
    /// preserving official error/background output rather than forcing a card.
    public static func resolve(
        call: NativeToolTerminalView?,
        result: NativeToolTerminalView?,
        settled: Bool
    ) -> NativeTerminalCardPresentation? {
        let terminalCall = call?.card == "terminal" ? call : nil
        if !settled {
            guard let terminalCall else { return nil }
            return NativeTerminalCardPresentation(
                command: terminalCall.title ?? "",
                description: terminalCall.description,
                cwd: terminalCall.cwd,
                output: nil,
                exitCode: nil,
                signal: nil,
                running: true
            )
        }

        guard let terminalResult = result, terminalResult.card == "terminal" else {
            return nil
        }
        return NativeTerminalCardPresentation(
            command: terminalResult.title ?? terminalCall?.title ?? "",
            description: terminalCall?.description,
            // An evicted call side cannot safely recover an explicit workdir
            // from a result that does not carry one. This matches the official
            // bare-prompt fallback rather than inventing a session path.
            cwd: terminalCall?.cwd,
            output: terminalResult.output,
            exitCode: terminalResult.exitCode,
            signal: terminalResult.signal,
            running: false
        )
    }

    /// Matches rc.2 `terminalFailed`: terminal exit status is result data, not a
    /// generic tool failure. A running card never reports a terminal failure.
    public var failed: Bool {
        !running && ((exitCode != nil && exitCode != 0) || signal != nil)
    }
}

/// Raw terminal output projection used by the native TerminalBlock counterpart.
/// It owns only line/height semantics; ANSI styled-span parity remains separate
/// from this safe text projection and never affects the copied Host raw output.
public struct NativeTerminalOutputPresentation: Equatable, Sendable {
    public let rawOutput: String
    public let lines: [String]
    public let isVisiblyEmpty: Bool

    public static func resolve(output: String?) -> NativeTerminalOutputPresentation? {
        guard let output else { return nil }
        let body = output.hasSuffix("\n") ? String(output.dropLast()) : output
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return .init(
            rawOutput: output,
            lines: lines,
            isVisiblyEmpty: lines.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }
}

/// Shared head/tail cap used by terminal details. The row passes `nil` maxLines
/// because rc.2 ToolRow expands terminal output without a cap; details uses the
/// primitive default 16-line cap.
public struct NativeTerminalOutputWindow: Equatable, Sendable {
    public let head: [String]
    public let tail: [String]
    public let hiddenCount: Int

    public static func resolve(lines: [String], maxLines: Int?, expanded: Bool) -> NativeTerminalOutputWindow {
        guard let maxLines, maxLines >= 0, !expanded, lines.count > maxLines else {
            return .init(head: lines, tail: [], hiddenCount: 0)
        }
        let hidden = lines.count - maxLines
        let headCount = (maxLines + 1) / 2
        let tailCount = maxLines - headCount
        return .init(
            head: Array(lines.prefix(headCount)),
            tail: tailCount == 0 ? [] : Array(lines.suffix(tailCount)),
            hiddenCount: hidden
        )
    }
}
