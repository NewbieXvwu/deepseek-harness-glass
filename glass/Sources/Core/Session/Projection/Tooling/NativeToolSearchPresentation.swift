import Foundation

struct NativeToolSearchLineMatch: Equatable, Sendable {
    let lineNumber: Double
    let line: String
}

struct NativeToolSearchFileGroup: Equatable, Sendable {
    let path: String
    let matches: [NativeToolSearchLineMatch]
}

/// Strict typed subset of the result-side official `card:'search'` view.
struct NativeToolSearchView: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case matches([NativeToolSearchFileGroup])
        case paths([String])
    }

    let title: String?
    let truncated: Bool
    let total: Double
    let shape: Shape
}

/// Result-side-only native `searchCardModel` projection. The search card
/// contains no call-time data, so running calls never enter this presentation.
struct NativeSearchCardPresentation: Equatable, Sendable {
    let title: String?
    let truncated: Bool
    let total: Double
    let shape: NativeToolSearchView.Shape
    /// The model accepts only text-block flatten supplied by Core. Callers must
    /// never substitute generic pretty JSON output for the official recovery.
    let recovery: String?

    static func resolve(
        result: NativeToolSearchView?,
        completed: Bool,
        textRecovery: String?
    ) -> NativeSearchCardPresentation? {
        guard completed, let result else { return nil }
        return .init(
            title: result.title,
            truncated: result.truncated,
            total: result.total,
            shape: result.shape,
            recovery: result.truncated ? textRecovery : nil
        )
    }

    var shownCount: Int {
        switch shape {
        case let .paths(paths): paths.count
        case let .matches(files): files.reduce(into: 0) { $0 += $1.matches.count }
        }
    }

    var fileCount: Int {
        guard case let .matches(files) = shape else { return 0 }
        return files.count
    }
}

/// A flattened SearchBlock row. Match file header collapse state is explicit so
/// card rendering does not need to reinterpret raw search view JSON.
struct NativeSearchRow: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case file, match, path }

    let kind: Kind
    let text: String
    let lineNumber: Double?
    let fileIndex: Int?
    let matchCount: Int?
    let collapsed: Bool
}

struct NativeSearchRowsPresentation: Equatable, Sendable {
    let rows: [NativeSearchRow]

    static func resolve(
        shape: NativeToolSearchView.Shape,
        collapsedFileIndices: Set<Int> = []
    ) -> NativeSearchRowsPresentation {
        switch shape {
        case let .paths(paths):
            return .init(rows: paths.map { .init(kind: .path, text: $0, lineNumber: nil, fileIndex: nil, matchCount: nil, collapsed: false) })
        case let .matches(files):
            var rows: [NativeSearchRow] = []
            for (index, file) in files.enumerated() {
                let collapsed = collapsedFileIndices.contains(index)
                rows.append(.init(kind: .file, text: file.path, lineNumber: nil, fileIndex: index, matchCount: file.matches.count, collapsed: collapsed))
                guard !collapsed else { continue }
                for match in file.matches {
                    rows.append(.init(kind: .match, text: match.line, lineNumber: match.lineNumber, fileIndex: index, matchCount: nil, collapsed: false))
                }
            }
            return .init(rows: rows)
        }
    }
}

/// SearchBlock's capped window, including its tail-header repair. The repair
/// consumes the tail's first match row so visible rows do not exceed `maxLines`.
struct NativeSearchWindowPresentation: Equatable, Sendable {
    let head: [NativeSearchRow]
    let tailHeader: NativeSearchRow?
    let tail: [NativeSearchRow]
    let hiddenCount: Int

    static func resolve(rows: [NativeSearchRow], maxLines: Int, expanded: Bool) -> NativeSearchWindowPresentation {
        guard maxLines >= 0, !expanded, rows.count > maxLines else {
            return .init(head: rows, tailHeader: nil, tail: [], hiddenCount: 0)
        }
        let hidden = rows.count - maxLines
        let headCount = (maxLines + 1) / 2
        let tailCount = maxLines - headCount
        let head = Array(rows.prefix(headCount))
        let naturalTail = tailCount == 0 ? [] : Array(rows.suffix(tailCount))
        guard let first = naturalTail.first,
              first.kind == .match,
              let index = first.fileIndex,
              !head.contains(where: { $0.kind == .file && $0.fileIndex == index }),
              let header = rows.first(where: { $0.kind == .file && $0.fileIndex == index })
        else { return .init(head: head, tailHeader: nil, tail: naturalTail, hiddenCount: hidden) }
        return .init(head: head, tailHeader: header, tail: Array(naturalTail.dropFirst()), hiddenCount: hidden)
    }
}
