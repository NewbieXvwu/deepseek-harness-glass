import XCTest

@testable import GlassCore

final class NativeTerminalANSIPresentationTests: XCTestCase {
    func testProjectsSGRSpansAcrossLinesAndHonorsAttributeClosers() {
        let output = NativeTerminalANSIPresentation.parse("plain \u{1B}[31mred\u{1B}[1m bold\u{1B}[22m plain-red\nnext\u{1B}[0m end")
        XCTAssertEqual(output.lines.count, 2)
        XCTAssertEqual(output.lines[0].map(\.text), ["plain ", "red", " bold", " plain-red"])
        XCTAssertNil(output.lines[0][0].style)
        XCTAssertEqual(output.lines[0][1].style?.foreground, .basic(.red))
        XCTAssertFalse(output.lines[0][1].style?.bold ?? true)
        XCTAssertTrue(output.lines[0][2].style?.bold ?? false)
        XCTAssertFalse(output.lines[0][3].style?.bold ?? true)
        XCTAssertEqual(output.lines[1].map(\.text), ["next", " end"])
        XCTAssertEqual(output.lines[1][0].style?.foreground, .basic(.red), "SGR state must thread across newlines")
        XCTAssertNil(output.lines[1][1].style)
    }

    func testStripsOSCAndInertControlsAndPreservesVisibleTabsAndBlankLines() {
        let output = NativeTerminalANSIPresentation.parse("\u{1B}]0;window title\u{7}a\u{0}\t\n\n\u{1B}[?25lvisible")
        XCTAssertEqual(output.lines.map { $0.map(\.text).joined() }, ["a\t", "", "visible"])
        XCTAssertFalse(output.requiresCursorReplay)
    }

    func testProjectsPaletteTruecolorAndHiddenWhileRejectingCursorControlsFromVisibleText() {
        let output = NativeTerminalANSIPresentation.parse("\u{1B}[38;5;208morange\u{1B}[48;2;1;2;3m bg\u{1B}[8m secret\u{1B}[28m!\r\u{8}\u{1B}[2K")
        XCTAssertEqual(output.lines[0].map(\.text), ["orange", " bg", " secret", "!"])
        XCTAssertEqual(output.lines[0][0].style?.foreground, .palette(208))
        XCTAssertEqual(output.lines[0][1].style?.background, .rgb(1, 2, 3))
        XCTAssertTrue(output.lines[0][2].style?.hidden ?? false)
        XCTAssertFalse(output.lines[0][3].style?.hidden ?? true)
        XCTAssertTrue(output.requiresCursorReplay)
        XCTAssertFalse(output.lines[0].map(\.text).joined().contains("\u{1B}"))
    }
}
