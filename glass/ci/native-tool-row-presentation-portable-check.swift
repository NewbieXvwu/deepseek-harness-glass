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
