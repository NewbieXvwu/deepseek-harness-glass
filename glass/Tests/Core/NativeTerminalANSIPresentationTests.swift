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

    func testProjectsPaletteTruecolorAndHiddenWhileRejectingControlsFromVisibleText() {
        let output = NativeTerminalANSIPresentation.parse("\u{1B}[38;5;208morange\u{1B}[48;2;1;2;3m bg\u{1B}[8m secret\u{1B}[28m!")
        XCTAssertEqual(output.lines[0].map(\.text), ["orange", " bg", " secret", "!"])
        XCTAssertEqual(output.lines[0][0].style?.foreground, .palette(208))
        XCTAssertEqual(output.lines[0][1].style?.background, .rgb(1, 2, 3))
        XCTAssertTrue(output.lines[0][2].style?.hidden ?? false)
        XCTAssertFalse(output.lines[0][3].style?.hidden ?? true)
        XCTAssertFalse(output.requiresCursorReplay)
        XCTAssertFalse(output.lines[0].map(\.text).joined().contains("\u{1B}"))
    }

    func testReplaysCarriageReturnEraseBackspaceAndStampedStyles() {
        let output = NativeTerminalANSIPresentation.parse("100%\rOK\nloading...\rOK\u{1B}[K\nabc\u{8}Z\nA\tB\rxy\n\u{1B}[31mred bad\u{1B}[0m\u{8}\u{8}\u{8}ok")
        XCTAssertEqual(output.lines.map { $0.map(\.text).joined() }, ["OK0%", "OK", "abZ", "xy      B", "red okd"])
        XCTAssertTrue(output.requiresCursorReplay)
        XCTAssertEqual(output.lines[4][0].style?.foreground, .basic(.red))
        XCTAssertNil(output.lines[4][1].style)
        XCTAssertEqual(output.lines[4][2].style?.foreground, .basic(.red), "unoverwritten cell keeps the state stamped when written")
    }
}
