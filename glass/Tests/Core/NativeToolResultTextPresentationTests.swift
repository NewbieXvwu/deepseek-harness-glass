import XCTest

@testable import GlassCore

final class NativeToolResultTextPresentationTests: XCTestCase {
    func testFlattensEveryRenderedBlockInOrderWithOneNewline() {
        XCTAssertEqual(
            NativeToolResultTextPresentation.flatten(
                parts: ["first", "{\n  \"type\" : \"reasoning\"\n}", "third"],
                errorName: nil,
                errorCode: nil
            ),
            "first\n{\n  \"type\" : \"reasoning\"\n}\nthird"
        )
    }

    func testEmptyResultUsesOnlyCompleteStructuredError() {
        XCTAssertEqual(
            NativeToolResultTextPresentation.flatten(
                parts: [],
                errorName: "ToolError",
                errorCode: "interrupted"
            ),
            "ToolError: interrupted"
        )
        XCTAssertNil(NativeToolResultTextPresentation.flatten(parts: [], errorName: nil, errorCode: "interrupted"))
        XCTAssertNil(NativeToolResultTextPresentation.flatten(parts: [], errorName: "ToolError", errorCode: nil))
        XCTAssertNil(NativeToolResultTextPresentation.flatten(parts: [], errorName: nil, errorCode: nil))
    }
}
