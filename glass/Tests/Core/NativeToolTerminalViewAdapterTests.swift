import XCTest

@testable import GlassCore
@testable import GlassPortableCore

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
