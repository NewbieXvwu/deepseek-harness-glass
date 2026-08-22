import XCTest

@testable import GlassPortableCore
@testable import GlassSpec
@testable import GlassUI

final class NativeToolRowModelTests: XCTestCase {
    func testFileToolSummaryUsesPathAndFilePathArgumentsBeforeRawJSON() {
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "write",
                arguments: #"{"file_path":"src/main.swift","content":"let value = 1"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "src/main.swift"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "edit",
                arguments: #"{"path":"README.md\nsecond line","old_string":"old"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "README.md"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "read",
                arguments: #"{"path":"first.md","file_path":"second.md"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "first.md"
        )
    }

    func testFilePathAuthorityIsLimitedToOfficialFileToolArguments() {
        XCTAssertEqual(
            NativeToolRowModel.filePath(
                toolName: "write",
                arguments: #"{"file_path":"src/main.swift"}"#
            ),
            "src/main.swift"
        )
        XCTAssertEqual(
            NativeToolRowModel.filePath(
                toolName: "edit",
                arguments: #"{"path":"README.md"}"#
            ),
            "README.md"
        )
        XCTAssertNil(NativeToolRowModel.filePath(toolName: "bash", arguments: #"{"path":"script.sh"}"#))
        XCTAssertNil(NativeToolRowModel.filePath(toolName: "write", arguments: "partial request"))
    }

    func testOfficialSummaryKeysCoverSearchBashReadAndCodeWithoutGrantingPaths() {
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "web_search",
                arguments: #"{"queries":["first query","second query"],"query":"ignored query"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "first query, second query"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "bash",
                arguments: #"{"command":"pwd","description":"show workspace"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "show workspace"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "web_fetch",
                arguments: #"{"url":"https://example.invalid/docs"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "https://example.invalid/docs"
        )
        XCTAssertNil(
            NativeToolRowModel.filePath(
                toolName: "web_fetch",
                arguments: #"{"url":"https://example.invalid/docs"}"#
            )
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "run_code",
                arguments: #"{"description":"render chart","code":"print(1)"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "render chart"
        )
    }

    func testExpandedBodyUsesOfficialCodeProgramAndGenericJSONFallback() {
        XCTAssertNil(NativeToolRowPresentation.body(toolName: "bash", arguments: ""))
        XCTAssertEqual(
            NativeToolRowPresentation.body(toolName: "bash", arguments: "partial request"),
            "partial request"
        )
        XCTAssertEqual(
            NativeToolRowPresentation.body(
                toolName: "run_code",
                arguments: #"{"description":"render chart","code":"print(1)\nprint(2)"}"#
            ),
            "print(1)\nprint(2)"
        )
        XCTAssertEqual(
            NativeToolRowPresentation.body(
                toolName: "bash",
                arguments: #"{"command":"pwd","description":"show workspace"}"#
            ),
            "{\n  \"command\" : \"pwd\",\n  \"description\" : \"show workspace\"\n}"
        )
    }

    func testTerminalPresentationUsesAdmittedCallAndResultViewsWithoutOverridingGenericResults() {
        let call = NativeToolTerminalView(
            card: "terminal",
            title: "pwd",
            description: "Show workspace",
            cwd: "sub"
        )
        let running = NativeTerminalCardPresentation.resolve(call: call, result: nil, settled: false)
        XCTAssertEqual(running?.command, "pwd")
        XCTAssertEqual(running?.description, "Show workspace")
        XCTAssertEqual(running?.cwd, "sub")
        XCTAssertTrue(running?.running == true)
        XCTAssertNil(running?.output)
        XCTAssertFalse(running?.failed == true)

        let settled = NativeTerminalCardPresentation.resolve(
            call: call,
            result: NativeToolTerminalView(
                card: "terminal",
                title: "pwd -P",
                output: "/workspace\\n",
                exitCode: 3
            ),
            settled: true
        )
        XCTAssertEqual(settled?.command, "pwd -P")
        XCTAssertEqual(settled?.output, "/workspace\\n")
        XCTAssertTrue(settled?.failed == true)

        XCTAssertNil(
            NativeTerminalCardPresentation.resolve(
                call: call,
                result: NativeToolTerminalView(card: "generic", output: "background started"),
                settled: true
            )
        )
        XCTAssertNil(
            NativeTerminalCardPresentation.resolve(
                call: NativeToolTerminalView(card: "unknown", title: "pwd"),
                result: nil,
                settled: false
            )
        )
    }

    func testTerminalPresentationRetainsResultOnlyWindowTruncationWithoutInventingCWD() {
        let presentation = NativeTerminalCardPresentation.resolve(
            call: nil,
            result: NativeToolTerminalView(card: "terminal", title: "echo hi", output: "hi", signal: "SIGKILL"),
            settled: true
        )
        XCTAssertEqual(presentation?.command, "echo hi")
        XCTAssertNil(presentation?.cwd)
        XCTAssertEqual(presentation?.output, "hi")
        XCTAssertEqual(presentation?.signal, "SIGKILL")
        XCTAssertTrue(presentation?.failed == true)
    }

    func testToolSummaryFallsBackSafelyForMalformedAndGenericArguments() {
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "write",
                arguments: "partial request\nremaining",
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "partial request"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "custom_tool",
                arguments: "payload\nremaining",
                isGeneric: true,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "custom_tool \(OfficialUISpec.Text.toolSummarySeparator) payload"
        )
    }
}
