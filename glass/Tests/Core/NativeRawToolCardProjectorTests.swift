import XCTest

@testable import GlassCore

final class NativeRawToolCardProjectorTests: XCTestCase {
    func testTerminalProjectsRunningAndSettledRc1Facts() throws {
        let running = invocation(
            name: "bash",
            arguments: #"{"command":"pwd -P","description":"Show cwd","workdir":"sub"}"#,
            state: .running,
            sessionCWD: "/workspace"
        )
        XCTAssertEqual(
            NativeRawToolCardProjector.terminal(running),
            .init(command: "pwd -P", description: "Show cwd", cwd: "/workspace/sub", output: nil, exitCode: nil, signal: nil, running: true)
        )

        let settled = invocation(
            name: "bash",
            arguments: #"{"command":"pwd -P","description":"Show cwd","workdir":"sub"}"#,
            state: .completed,
            resultContent: [text("/workspace/sub\n\n[exit code: 3]")],
            resultIsError: false,
            sessionCWD: "/workspace"
        )
        XCTAssertEqual(
            NativeRawToolCardProjector.terminal(settled),
            .init(command: "pwd -P", description: "Show cwd", cwd: "/workspace/sub", output: "/workspace/sub\n", exitCode: 3, signal: nil, running: false)
        )
        XCTAssertNil(NativeRawToolCardProjector.terminal(invocation(name: "bash", arguments: #"{"command":"sleep 1","description":"bg","run_in_background":true}"#, state: .running)))
    }

    func testReadProjectsStrictResultMetaAndEnvelope() throws {
        let result = invocation(
            name: "read",
            arguments: #"{"file_path":"README.md","offset":5,"limit":2}"#,
            state: .completed,
            resultContent: [text("<path>/workspace/README.md</path>\n<type>file</type>\n<content>\n# Heading\nbody\n</content>")],
            resultMeta: .object([
                "path": .string("/workspace/README.md"),
                "offset": .number(5),
                "lines": .array([
                    .object(["number": .number(5), "text": .string("# Heading")]),
                    .object(["number": .number(6), "text": .string("body")]),
                ]),
                "totalLines": .number(10),
                "lang": .string("markdown"),
            ]),
            resultIsError: false,
            sessionCWD: "/workspace"
        )
        XCTAssertEqual(
            NativeRawToolCardProjector.read(result),
            .init(label: "README.md", lines: [.init(number: 5, text: "# Heading"), .init(number: 6, text: "body")], totalLines: 10, lang: "markdown")
        )

        var malformed = result
        malformed.resultMeta = .object([
            "path": .string("README.md"),
            "offset": .number(1),
            "lines": .array([.object(["number": .number(2), "text": .string("outside")])]),
            "totalLines": .number(1),
        ])
        XCTAssertNil(NativeRawToolCardProjector.read(malformed))
    }

    func testDiffUsesCallIntentWhileRunningAndAppliedMetaWhenSettled() throws {
        let running = invocation(
            name: "edit",
            arguments: #"{"file_path":"draft.txt","old_string":"before","new_string":"intent"}"#,
            state: .running
        )
        XCTAssertEqual(NativeRawToolCardProjector.diff(running)?.source, .call)
        XCTAssertEqual(NativeRawToolCardProjector.diff(running)?.diffs.first?.newText, "intent")

        let settled = invocation(
            name: "edit",
            arguments: #"{"file_path":"draft.txt","old_string":"before","new_string":"intent"}"#,
            state: .completed,
            resultMeta: .object([
                "diffs": .array([.object([
                    "path": .string("draft.txt"),
                    "oldText": .string("before"),
                    "newText": .string("applied"),
                ])]),
            ]),
            resultIsError: false
        )
        XCTAssertEqual(NativeRawToolCardProjector.diff(settled)?.source, .result)
        XCTAssertEqual(NativeRawToolCardProjector.diff(settled)?.diffs.first?.newText, "applied")
    }

    func testSearchProjectsGrepAndGlobMeta() throws {
        let grep = invocation(
            name: "grep",
            arguments: #"{"pattern":"TODO","path":"src"}"#,
            state: .completed,
            resultContent: [text("fallback")],
            resultMeta: .object([
                "shape": .string("matches"),
                "truncated": .bool(true),
                "total": .number(1),
                "files": .array([.object([
                    "path": .string("src/a.swift"),
                    "matches": .array([.object(["lineNumber": .number(7), "line": .string("// TODO")])]),
                ])]),
            ]),
            resultIsError: false
        )
        let projected = try XCTUnwrap(NativeRawToolCardProjector.search(grep))
        XCTAssertTrue(projected.truncated)
        XCTAssertEqual(projected.total, 1)
        XCTAssertEqual(projected.recovery, "fallback")
        XCTAssertEqual(projected.shownCount, 1)

        let glob = invocation(
            name: "glob",
            arguments: #"{"pattern":"**/*.swift"}"#,
            state: .completed,
            resultMeta: .object([
                "shape": .string("paths"),
                "truncated": .bool(false),
                "total": .number(2),
                "paths": .array([.string("a.swift"), .string("b.swift")]),
            ]),
            resultIsError: false
        )
        XCTAssertEqual(NativeRawToolCardProjector.search(glob)?.shownCount, 2)
    }

    func testWebProjectsSearchAndFetchMetaAndRejectsSubagentCalls() throws {
        let search = invocation(
            name: "web_search",
            arguments: #"{"queries":["deepseek harness"]}"#,
            state: .completed,
            resultMeta: .object([
                "truncated": .bool(false),
                "answer": .string("answer"),
                "sources": .array([.object([
                    "url": .string("https://example.com/a"),
                    "title": .string("A"),
                    "snippet": .string("S"),
                    "publishedAt": .string("2026-01-01"),
                ])]),
            ]),
            resultIsError: false
        )
        let projected = try XCTUnwrap(NativeRawToolCardProjector.web(search))
        guard case let .search(answer, sources, truncated) = projected.kind else { return XCTFail("expected search") }
        XCTAssertEqual(answer, "answer")
        XCTAssertEqual(sources.count, 1)
        XCTAssertFalse(truncated)

        let fetch = invocation(
            name: "web_fetch",
            arguments: #"{"url":"https://example.com"}"#,
            state: .completed,
            resultMeta: .object(["truncated": .bool(true), "url": .string("https://example.com"), "statusCode": .number(200)]),
            resultIsError: false
        )
        guard case let .fetch(url, statusCode, truncated) = try XCTUnwrap(NativeRawToolCardProjector.web(fetch)).kind else { return XCTFail("expected fetch") }
        XCTAssertEqual(url, "https://example.com")
        XCTAssertEqual(statusCode, 200)
        XCTAssertTrue(truncated)

        var child = search
        child.parentCallID = "parent"
        XCTAssertNil(NativeRawToolCardProjector.web(child))
    }

    private func invocation(
        name: String,
        arguments: String,
        state: NativeSessionStore.ToolInvocation.State,
        resultContent: [JSONValue]? = nil,
        resultMeta: JSONValue? = nil,
        resultIsError: Bool? = nil,
        sessionCWD: String? = nil
    ) -> NativeSessionStore.ToolInvocation {
        .init(
            id: "call-1",
            name: name,
            arguments: arguments,
            output: nil,
            textOutput: nil,
            errorName: nil,
            errorCode: nil,
            state: state,
            sequence: 1,
            resultContent: resultContent,
            resultMeta: resultMeta,
            resultIsError: resultIsError,
            parentCallID: nil,
            sessionCWD: sessionCWD
        )
    }

    private func text(_ value: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(value)])
    }
}
