import Foundation

@main
struct NativeToolRowPresentationPortableCheck {
    static func main() throws {
        try expectEqual(
            NativeToolRowModel.summary(
                toolName: "web_search",
                arguments: #"{"queries":["first query","second query"],"query":"ignored query"}"#,
                isGeneric: false,
                separator: " · "
            ),
            "first query, second query",
            "search query list must outrank scalar query"
        )
        try expectEqual(
            NativeToolRowModel.summary(
                toolName: "bash",
                arguments: #"{"command":"pwd","description":"show workspace"}"#,
                isGeneric: false,
                separator: " · "
            ),
            "show workspace",
            "bash description must outrank command"
        )
        try expectEqual(
            NativeToolRowModel.summary(
                toolName: "web_fetch",
                arguments: #"{"url":"https://example.invalid/docs"}"#,
                isGeneric: false,
                separator: " · "
            ),
            "https://example.invalid/docs",
            "read-family URL must remain visible in collapsed summary"
        )
        guard NativeToolRowModel.filePath(
            toolName: "web_fetch",
            arguments: #"{"url":"https://example.invalid/docs"}"#
        ) == nil else {
            throw CheckFailure("URL summary must not become an openable project path")
        }
        try expectEqual(
            NativeToolRowPresentation.body(
                toolName: "run_code",
                arguments: #"{"description":"render chart","code":"print(1)\nprint(2)"}"#
            ),
            "print(1)\nprint(2)",
            "code body must be extracted from the JSON envelope"
        )
        guard NativeToolRowPresentation.body(toolName: "bash", arguments: "") == nil else {
            throw CheckFailure("empty arguments must omit the input body")
        }
        try expectEqual(
            NativeToolRowPresentation.body(toolName: "bash", arguments: "partial request"),
            "partial request",
            "malformed arguments must remain raw rather than being discarded"
        )
        guard let pretty = NativeToolRowPresentation.body(
            toolName: "bash",
            arguments: #"{"command":"pwd","description":"show workspace"}"#
        ), pretty.contains("\n"), pretty.contains("\"command\""), pretty.contains("\"description\"") else {
            throw CheckFailure("generic JSON arguments must retain a pretty, complete body")
        }

        let call = NativeToolTerminalView(
            card: "terminal",
            title: "pwd",
            description: "Show workspace",
            cwd: "sub"
        )
        guard let running = NativeTerminalCardPresentation.resolve(call: call, result: nil, settled: false) else {
            throw CheckFailure("terminal call view must derive a running card")
        }
        try expectEqual(running.command, "pwd", "running terminal card must use call title")
        guard running.running, running.output == nil, running.cwd == "sub" else {
            throw CheckFailure("running terminal card must retain only call-side material")
        }

        guard let settled = NativeTerminalCardPresentation.resolve(
            call: call,
            result: NativeToolTerminalView(card: "terminal", title: "pwd -P", output: "/workspace\\n", exitCode: 3),
            settled: true
        ) else {
            throw CheckFailure("terminal result view must derive a settled card")
        }
        try expectEqual(settled.command, "pwd -P", "result title must replace call title")
        try expectEqual(settled.output, "/workspace\\n", "terminal result output must be retained")
        guard settled.failed else { throw CheckFailure("nonzero settled terminal exit must surface as terminal failure") }

        guard NativeTerminalCardPresentation.resolve(
            call: call,
            result: NativeToolTerminalView(card: "generic", output: "background"),
            settled: true
        ) == nil else {
            throw CheckFailure("generic settled result must not inherit a terminal call card")
        }
        guard NativeTerminalCardPresentation.resolve(
            call: NativeToolTerminalView(card: "unknown", title: "pwd"),
            result: nil,
            settled: false
        ) == nil else {
            throw CheckFailure("unknown running card must remain generic")
        }
        guard let truncated = NativeTerminalCardPresentation.resolve(
            call: nil,
            result: NativeToolTerminalView(card: "terminal", title: "echo hi", output: "hi"),
            settled: true
        ), truncated.cwd == nil, truncated.command == "echo hi" else {
            throw CheckFailure("truncated call side must retain result title without inventing cwd")
        }

        try expectEqual(
            NativeToolResultTextPresentation.flatten(
                parts: ["first", "{\n  \"type\" : \"reasoning\"\n}", "third"],
                errorName: nil,
                errorCode: nil
            ),
            "first\n{\n  \"type\" : \"reasoning\"\n}\nthird",
            "result text must retain every block in original order with one newline"
        )
        try expectEqual(
            NativeToolResultTextPresentation.flatten(
                parts: [],
                errorName: "ToolError",
                errorCode: "interrupted"
            ),
            "ToolError: interrupted",
            "empty result must use only its structured error fallback"
        )
        guard NativeToolResultTextPresentation.flatten(parts: [], errorName: nil, errorCode: "interrupted") == nil else {
            throw CheckFailure("partial structured error must not invent fallback prose")
        }

        let read = NativeToolReadView(
            card: "read",
            title: "README preview",
            path: "/workspace/README.md",
            lines: [
                .init(number: 5, text: "# Heading"),
                .init(number: 6, text: "body"),
            ],
            totalLines: 10,
            lang: "markdown"
        )
        guard let readCard = NativeReadCardPresentation.resolve(result: read, completed: true) else {
            throw CheckFailure("complete settled read result must admit a read card")
        }
        try expectEqual(readCard.label, "README preview", "read replacement title must outrank path")
        guard readCard.lines.map(\.number) == [5, 6], readCard.totalLines == 10, readCard.lang == "markdown" else {
            throw CheckFailure("read card must retain source line numbers, total count, and language")
        }
        guard NativeReadCardPresentation.resolve(result: read, completed: false) == nil else {
            throw CheckFailure("running read must remain generic without a result card")
        }
        guard NativeReadCardPresentation.resolve(
            result: NativeToolReadView(card: "unknown", title: nil, path: "README.md", lines: [], totalLines: 0, lang: nil),
            completed: true
        ) == nil else {
            throw CheckFailure("unknown result card must not become a read card")
        }
        guard NativeReadCardPresentation.resolve(
            result: NativeToolReadView(card: "read", title: nil, path: "README.md", lines: [.init(number: 1, text: "one")], totalLines: 0, lang: nil),
            completed: true
        ) == nil else {
            throw CheckFailure("read result with fewer total lines than its window must fail closed")
        }
        let twentyLines = (1 ... 20).map { NativeToolReadLine(number: $0, text: "line-\($0)") }
        let chatWindow = NativeReadCardWindowPresentation.resolve(lines: twentyLines, maxLines: 8, expanded: false)
        guard chatWindow.head.map(\.number) == [1, 2, 3, 4],
              chatWindow.tail.map(\.number) == [17, 18, 19, 20],
              chatWindow.hiddenCount == 12 else {
            throw CheckFailure("chat read cap must split 8 visible lines into four head/four tail lines")
        }
        let detailsWindow = NativeReadCardWindowPresentation.resolve(lines: twentyLines, maxLines: 16, expanded: false)
        guard detailsWindow.head.map(\.number) == Array(1 ... 8),
              detailsWindow.tail.map(\.number) == Array(13 ... 20),
              detailsWindow.hiddenCount == 4 else {
            throw CheckFailure("details read cap must split 16 visible lines into eight head/eight tail lines")
        }
        let expandedRead = NativeReadCardWindowPresentation.resolve(lines: twentyLines, maxLines: 8, expanded: true)
        guard expandedRead.head == twentyLines, expandedRead.tail.isEmpty, expandedRead.hiddenCount == 0 else {
            throw CheckFailure("expanded read card must restore its whole source window")
        }
        let zeroCap = NativeReadCardWindowPresentation.resolve(lines: twentyLines, maxLines: 0, expanded: false)
        guard zeroCap.head.isEmpty, zeroCap.tail.isEmpty, zeroCap.hiddenCount == 20 else {
            throw CheckFailure("zero read cap must hide every line without inventing a head/tail line")
        }

        let callDiff = NativeToolDiffView(card: "diff", diffs: [.init(path: "draft.txt", oldText: "before", newText: "intent")])
        let resultDiff = NativeToolDiffView(card: "diff", diffs: [.init(path: "draft.txt", oldText: "before", newText: "applied")])
        guard NativeDiffCardPresentation.resolve(call: callDiff, result: nil, settled: false)?.source == .call else {
            throw CheckFailure("running typed diff must use the intended call-side hunk")
        }
        guard let settledDiff = NativeDiffCardPresentation.resolve(call: callDiff, result: resultDiff, settled: true),
              settledDiff.source == .result,
              settledDiff.diffs.first?.newText == "applied" else {
            throw CheckFailure("settled typed diff must replace call intent with result-side applied hunk")
        }
        guard NativeDiffCardPresentation.resolve(call: callDiff, result: nil, settled: true) == nil,
              NativeDiffCardPresentation.resolve(call: nil, result: NativeToolDiffView(card: "unknown", diffs: resultDiff.diffs), settled: true) == nil else {
            throw CheckFailure("missing or unknown settled diff must remain generic")
        }
        let diffRows = NativeDiffRowsPresentation.resolve(diffs: [
            .init(path: "a.swift", oldText: "old\n", newText: "new\n\n"),
            .init(path: "a.swift", oldText: nil, newText: "second"),
            .init(path: "b.swift", oldText: "", newText: "created"),
        ])
        guard diffRows.rows.map(\.kind) == [.path, .deletion, .addition, .addition, .gap, .addition, .path, .addition],
              diffRows.rows.map(\.text) == ["a.swift", "old", "new", "", "⋯", "second", "b.swift", "created"],
              diffRows.added == 4,
              diffRows.removed == 1,
              diffRows.files == 2 else {
            throw CheckFailure("diff rows must preserve source terminator, interior blank, same-path gap, and distinct-file totals")
        }

        let searchView = NativeToolSearchView(
            title: "Grep preview",
            truncated: true,
            total: 9,
            shape: .matches([.init(path: "src/main.swift", matches: [.init(lineNumber: 7, line: "needle")])])
        )
        guard let searchCard = NativeSearchCardPresentation.resolve(
            result: searchView,
            completed: true,
            textRecovery: "Full output stored at /tmp/search"
        ), searchCard.recovery == "Full output stored at /tmp/search", searchCard.shownCount == 1, searchCard.fileCount == 1 else {
            throw CheckFailure("truncated settled search must retain typed matches and text-only recovery")
        }
        guard NativeSearchCardPresentation.resolve(result: searchView, completed: false, textRecovery: "recovery") == nil else {
            throw CheckFailure("running search must remain generic because search cards are result-side only")
        }
        let uncappedSearch = NativeToolSearchView(title: nil, truncated: false, total: 1, shape: .paths(["README.md"]))
        guard NativeSearchCardPresentation.resolve(result: uncappedSearch, completed: true, textRecovery: "must hide")?.recovery == nil else {
            throw CheckFailure("uncapped search must omit recovery text")
        }
        let searchRows = NativeSearchRowsPresentation.resolve(shape: .matches([
            .init(path: "a.swift", matches: [.init(lineNumber: 1, line: "a1")]),
            .init(path: "b.swift", matches: [.init(lineNumber: 2, line: "b2"), .init(lineNumber: 3, line: "b3")]),
        ])).rows
        let searchWindow = NativeSearchWindowPresentation.resolve(rows: searchRows, maxLines: 3, expanded: false)
        guard searchWindow.head.map(\.text) == ["a.swift", "a1"],
              searchWindow.tailHeader?.text == "b.swift",
              searchWindow.tail.isEmpty,
              searchWindow.hiddenCount == 2 else {
            throw CheckFailure("search tail must restore its owning file header without exceeding cap")
        }

        let webSearch = NativeToolWebView(kind: .search(
            answer: "A sourced answer",
            sources: [.init(url: "https://example.com/article", title: "Example", snippet: "excerpt", publishedAt: "2026-08-22")],
            truncated: true
        ))
        guard NativeWebCardPresentation.resolve(result: webSearch, completed: true) != nil,
              NativeWebCardPresentation.resolve(result: webSearch, completed: false) == nil else {
            throw CheckFailure("web cards must be result-side only")
        }
        let safeWeb = NativeSafeWebLink.resolve(url: "https://example.com/article", title: nil)
        guard safeWeb.label == "example.com", safeWeb.destination?.absoluteString == "https://example.com/article" else {
            throw CheckFailure("http(s) web source must retain its safe external destination and hostname label")
        }
        let unsafeWeb = NativeSafeWebLink.resolve(url: "javascript:alert(1)", title: nil)
        guard unsafeWeb.destination == nil, unsafeWeb.label == "javascript:alert(1)" else {
            throw CheckFailure("non-http web source must remain an inert raw-text label")
        }
        print("native tool row presentation portable check passed")
    }

    private static func expectEqual(_ actual: String?, _ expected: String, _ message: String) throws {
        guard actual == expected else { throw CheckFailure("\(message): expected \(expected), got \(actual ?? "nil")") }
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
