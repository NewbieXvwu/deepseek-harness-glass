import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeTodoDockTests: XCTestCase {
    func testTodoDockHidesForMissingOrEmptyHostWholeList() {
        XCTAssertFalse(NativeTodoDockPresentation.isVisible(nil))
        XCTAssertFalse(NativeTodoDockPresentation.isVisible([]))
        XCTAssertTrue(NativeTodoDockPresentation.isVisible([.init(content: "Inspect", status: .pending)]))
    }

    func testTodoDockStartsCollapsedAndUsesOfficialProgressSegments() {
        let todos: [CoreTodoItem] = [
            .init(content: "Inspect", status: .completed),
            .init(content: "Implement", status: .inProgress),
            .init(content: "Verify", status: .pending),
            .init(content: "Ship", status: .pending),
        ]

        XCTAssertEqual(
            NativeTodoDockPresentation.progressLabel(for: todos),
            "1 completed\u{2002}·\u{2002}1 in progress\u{2002}·\u{2002}2 pending"
        )
        XCTAssertEqual(
            NativeTodoDockPresentation.progressLabel(for: [.init(content: "Ship", status: .completed)]),
            OfficialUISpec.Text.todoProgressDone(1),
            "zero-count segments are omitted exactly as in RC8 TodoPanel"
        )
    }

    func testTodoDockProgressRingUsesOfficialOneSecondSpinAndReduceMotionStaticFallback() {
        XCTAssertEqual(NativeTodoDockPresentation.progressSpinDuration(reduceMotion: false), 1)
        XCTAssertNil(NativeTodoDockPresentation.progressSpinDuration(reduceMotion: true))
    }
}
