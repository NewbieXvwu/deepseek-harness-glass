import XCTest

@testable import GlassCore

final class NativeToolTerminalViewAdapterTests: XCTestCase {
    func testTerminalAdapterRetainsOnlyOfficiallyTypedTerminalFields() {
        let view = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("terminal"),
            "title": .string("pwd -P"),
            "description": .string("ignored on result side"),
            "cwd": .string("sub"),
            "output": .string("/workspace\n"),
            "exitCode": .number(3),
            "signal": .string("SIGTERM"),
            "pluginDetail": .object(["unsafe": .bool(true)]),
        ]))

        XCTAssertEqual(
            view.nativeTerminalView,
            NativeToolTerminalView(
                card: "terminal",
                title: "pwd -P",
                description: "ignored on result side",
                cwd: "sub",
                output: "/workspace\n",
                exitCode: 3,
                signal: "SIGTERM"
            )
        )
    }

    func testTerminalAdapterFailsClosedForMissingCardOrNonIntegralExitCode() {
        XCTAssertNil(ToolEventViewDTO(for: "call", view: .object(["title": .string("pwd")])).nativeTerminalView)
        XCTAssertEqual(
            ToolEventViewDTO(for: "result", view: .object([
                "card": .string("terminal"),
                "exitCode": .number(3.5),
            ])).nativeTerminalView?.exitCode,
            nil
        )
        XCTAssertEqual(
            ToolEventViewDTO(for: "result", view: .object([
                "card": .string("unknown-plugin-card"),
                "output": .string("opaque"),
            ])).nativeTerminalView?.card,
            "unknown-plugin-card"
        )
    }
}

final class NativeTerminalOutputPresentationTests: XCTestCase {
    func testOutputProjectionDropsOneTerminatorPreservesInteriorBlankAndCapsDetailsOnly() throws {
        let projection = try XCTUnwrap(NativeTerminalOutputPresentation.resolve(output: "one\ntwo\n\n"))
        XCTAssertEqual(projection.rawOutput, "one\ntwo\n\n")
        XCTAssertEqual(projection.lines, ["one", "two", ""])
        XCTAssertFalse(projection.isVisiblyEmpty)

        let lines = (1...20).map(String.init)
        let details = NativeTerminalOutputWindow.resolve(lines: lines, maxLines: 16, expanded: false)
        XCTAssertEqual(details.head, Array(lines.prefix(8)))
        XCTAssertEqual(details.tail, Array(lines.suffix(8)))
        XCTAssertEqual(details.hiddenCount, 4)
        let row = NativeTerminalOutputWindow.resolve(lines: lines, maxLines: nil, expanded: false)
        XCTAssertEqual(row.head, lines)
        XCTAssertTrue(row.tail.isEmpty)
        XCTAssertEqual(row.hiddenCount, 0)
        XCTAssertEqual(NativeTerminalOutputWindow.resolve(lines: lines, maxLines: 16, expanded: true).head, lines)
    }

    func testOutputProjectionKeepsRawCopyTextButTreatsWhitespaceOnlyAsEmpty() throws {
        let whitespace = try XCTUnwrap(NativeTerminalOutputPresentation.resolve(output: " \n\t\n"))
        XCTAssertEqual(whitespace.rawOutput, " \n\t\n")
        XCTAssertTrue(whitespace.isVisiblyEmpty)
        XCTAssertNil(NativeTerminalOutputPresentation.resolve(output: nil))
    }
}
