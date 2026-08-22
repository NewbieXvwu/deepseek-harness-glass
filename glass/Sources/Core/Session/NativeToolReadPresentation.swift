import Foundation

/// A line in the Host-authoritative `card:'read'` result view. File line
/// numbers are retained rather than re-indexed, so a windowed read preserves
/// the source file's own numbering.
struct NativeToolReadLine: Equatable, Sendable {
    let number: Int
    let text: String
}

/// Typed subset of the official read render intent. Core's JSON adapter creates
/// this only after validating every required field; a renderer never decodes an
/// arbitrary plugin dictionary itself.
struct NativeToolReadView: Equatable, Sendable {
    let card: String
    let title: String?
    let path: String
    let lines: [NativeToolReadLine]
    let totalLines: Int
    let lang: String?
}

/// Result-side-only native equivalent of rc.2 `readCardModel`. It intentionally
/// does not infer content from call arguments: a running read and every failed,
/// unknown, or malformed settled result remain on the raw generic path.
struct NativeReadCardPresentation: Equatable, Sendable {
    let label: String
    let lines: [NativeToolReadLine]
    let totalLines: Int
    let lang: String?

    static func resolve(
        result: NativeToolReadView?,
        completed: Bool
    ) -> NativeReadCardPresentation? {
        guard completed,
              let result,
              result.card == "read",
              result.totalLines >= result.lines.count
        else { return nil }
        return NativeReadCardPresentation(
            // The caller has no admitted session cwd/home in this Foundation
            // seam. A replacement title wins; otherwise preserve the Host path
            // as authored instead of guessing a relative label.
            label: result.title ?? result.path,
            lines: result.lines,
            totalLines: result.totalLines,
            lang: result.lang
        )
    }
}

/// The structural portion of rc.2 `ReadBlock` head/tail capping. It carries no
/// display copy or UI state: SwiftUI owns the eventual expand control only after
/// its official localization and AX contract are separately admitted.
struct NativeReadCardWindowPresentation: Equatable, Sendable {
    let head: [NativeToolReadLine]
    let tail: [NativeToolReadLine]
    let hiddenCount: Int

    static func resolve(lines: [NativeToolReadLine], maxLines: Int, expanded: Bool) -> NativeReadCardWindowPresentation {
        guard maxLines >= 0, !expanded, lines.count > maxLines else {
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
