import Foundation

/// One Host-authoritative diff hunk. `oldText == nil` is the official new-file
/// / overwrite representation; an empty `newText` remains distinct from a
/// missing field and permits a full deletion.
struct NativeToolDiffHunk: Equatable, Sendable {
    let path: String
    let oldText: String?
    let newText: String
}

/// Typed subset of an official `card:'diff'` render intent. It contains only
/// validated hunk data; view title is intentionally absent because rc.2 row
/// titles come from the call model, not from the diff card.
struct NativeToolDiffView: Equatable, Sendable {
    let card: String
    let diffs: [NativeToolDiffHunk]
}

/// Native equivalent of rc.2 `diffCardModel` selection. While running, only a
/// typed call-side intended diff is eligible. Once settled, the result-side
/// applied diff entirely replaces the call side, including when history has
/// truncated the call head.
struct NativeDiffCardPresentation: Equatable, Sendable {
    let diffs: [NativeToolDiffHunk]
    let source: Source

    enum Source: Equatable, Sendable {
        case call
        case result
    }

    static func resolve(
        call: NativeToolDiffView?,
        result: NativeToolDiffView?,
        settled: Bool
    ) -> NativeDiffCardPresentation? {
        let selected = settled ? result : call
        guard let selected, selected.card == "diff", !selected.diffs.isEmpty else { return nil }
        return .init(diffs: selected.diffs, source: settled ? .result : .call)
    }
}

/// Foundation-only structural result of DiffBlock's flat row derivation. Prefix
/// formatting, colors and buttons belong to SwiftUI; the hunk authority, line
/// terminator rules and counts remain testable without AppKit.
struct NativeDiffRowsPresentation: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case path, deletion, addition, gap }

    struct Row: Equatable, Sendable {
        let kind: Kind
        let text: String
    }

    let rows: [Row]
    let added: Int
    let removed: Int
    let files: Int

    static func resolve(diffs: [NativeToolDiffHunk]) -> NativeDiffRowsPresentation {
        var rows: [Row] = []
        var paths: Set<String> = []
        var added = 0
        var removed = 0
        var previousPath: String?

        for diff in diffs {
            paths.insert(diff.path)
            rows.append(.init(kind: diff.path == previousPath ? .gap : .path, text: diff.path == previousPath ? "⋯" : diff.path))
            previousPath = diff.path
            if let oldText = diff.oldText {
                for line in contentLines(oldText) {
                    rows.append(.init(kind: .deletion, text: line))
                    removed += 1
                }
            }
            for line in contentLines(diff.newText) {
                rows.append(.init(kind: .addition, text: line))
                added += 1
            }
        }
        return .init(rows: rows, added: added, removed: removed, files: paths.count)
    }

    private static func contentLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let body = text.hasSuffix("\n") ? String(text.dropLast()) : text
        return body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

/// Structural DiffBlock head/tail cap. It mirrors the shared primitive rule and
/// carries no text or UI state so row/details can use their distinct 8/16 caps.
struct NativeDiffWindowPresentation: Equatable, Sendable {
    let head: [NativeDiffRowsPresentation.Row]
    let tail: [NativeDiffRowsPresentation.Row]
    let hiddenCount: Int

    static func resolve(
        rows: [NativeDiffRowsPresentation.Row],
        maxLines: Int,
        expanded: Bool
    ) -> NativeDiffWindowPresentation {
        guard maxLines >= 0, !expanded, rows.count > maxLines else {
            return .init(head: rows, tail: [], hiddenCount: 0)
        }
        let hidden = rows.count - maxLines
        let headCount = (maxLines + 1) / 2
        let tailCount = maxLines - headCount
        return .init(
            head: Array(rows.prefix(headCount)),
            tail: tailCount == 0 ? [] : Array(rows.suffix(tailCount)),
            hiddenCount: hidden
        )
    }
}
