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
/// It parses spans once over the complete Host output so SGR state can thread
/// across lines, but preserves raw output untouched for clipboard copying.
public struct NativeTerminalOutputPresentation: Equatable, Sendable {
    public let rawOutput: String
    public let ansiLines: [[NativeTerminalANSISpan]]
    public let lines: [String]
    public let isVisiblyEmpty: Bool
    public let requiresCursorReplay: Bool

    public static func resolve(output: String?) -> NativeTerminalOutputPresentation? {
        guard let output else { return nil }
        let parsed = NativeTerminalANSIPresentation.parse(output)
        // rc.2 drops the parsed terminal newline, including `line\\nESC[0m`:
        // only a final fully empty parsed line is a terminator; a preceding
        // blank line remains visible.
        let ansiLines = parsed.lines.count > 1 && (parsed.lines.last?.allSatisfy { $0.text.isEmpty } ?? false)
            ? Array(parsed.lines.dropLast())
            : parsed.lines
        let lines = ansiLines.map { $0.map(\.text).joined() }
        return .init(
            rawOutput: output,
            ansiLines: ansiLines,
            lines: lines,
            isVisiblyEmpty: ansiLines.allSatisfy { line in
                line.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            },
            requiresCursorReplay: parsed.requiresCursorReplay
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

/// The typed-span counterpart of `NativeTerminalOutputWindow`. It shares the
/// exact head/tail counts but never reparses individual lines, preserving SGR
/// state that began before a capped tail line.
public struct NativeTerminalANSILineWindow: Equatable, Sendable {
    public let head: [[NativeTerminalANSISpan]]
    public let tail: [[NativeTerminalANSISpan]]
    public let hiddenCount: Int

    public static func resolve(
        lines: [[NativeTerminalANSISpan]],
        maxLines: Int?,
        expanded: Bool
    ) -> NativeTerminalANSILineWindow {
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
