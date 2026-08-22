import XCTest

@testable import GlassCore

final class NativeToolTodoPresentationTests: XCTestCase {
    func testProjectsCompletedCountFirstActiveAndParallelSuffix() throws {
        let summary = try XCTUnwrap(NativeToolTodoPresentation.resolve(
            toolName: "todo_write",
            arguments: #"{"todos":[{"content":"done","status":"completed"},{"content":"write renderer","status":"in_progress"},{"content":"run checks","status":"in_progress"},{"content":"later","status":"pending"}]}"#
        ))
        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.activeContent, "write renderer")
        XCTAssertEqual(summary.activeExtra, 1)
    }

    func testRetainsCountsButOmitsSuffixWhenFirstActiveContentIsInvalid() throws {
        let summary = try XCTUnwrap(NativeToolTodoPresentation.resolve(
            toolName: "todo_write",
            arguments: #"{"todos":[{"status":"in_progress"},{"content":"later active","status":"in_progress"},{"content":"done","status":"completed"}]}"#
        ))
        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.total, 3)
        XCTAssertNil(summary.activeContent)
        XCTAssertEqual(summary.activeExtra, 0)
    }

    func testRejectsUnknownToolMalformedEnvelopeAndNullTodoItem() {
        XCTAssertNil(NativeToolTodoPresentation.resolve(toolName: "todo_write", arguments: "not JSON"))
        XCTAssertNil(NativeToolTodoPresentation.resolve(toolName: "todo_write", arguments: #"{"todos":null}"#))
        XCTAssertNil(NativeToolTodoPresentation.resolve(toolName: "todo_write", arguments: #"{"todos":[null]}"#))
        XCTAssertNil(NativeToolTodoPresentation.resolve(toolName: "fx_todo_write", arguments: #"{"todos":[]}"#))
        XCTAssertEqual(
            NativeToolTodoPresentation.resolve(toolName: "todo_write", arguments: #"{"todos":[]}"#),
            .init(done: 0, total: 0, activeContent: nil, activeExtra: 0)
        )
    }
}
