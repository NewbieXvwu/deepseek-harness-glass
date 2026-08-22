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
