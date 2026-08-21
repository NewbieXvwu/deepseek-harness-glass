import XCTest

@testable import GlassUI

final class NativeProducedFilesLayoutTests: XCTestCase {
    func testEmptyPathsFailClosedBeforeAnyLayoutMeasurement() {
        XCTAssertFalse(NativeProducedFilesLayout.shouldRender(paths: []))
        XCTAssertTrue(NativeProducedFilesLayout.shouldRender(paths: ["out/index.html"]))
    }

    func testKeepsCandidateCapUntilLaneHasAUsableMeasurement() {
        XCTAssertEqual(
            NativeProducedFilesLayout.shownCount(
                available: 0,
                chipWidths: [44, 48, 52],
                moreWidthsByHidden: [1: 44, 2: 44, 3: 44, 4: 44],
                totalCount: 4,
                gap: 8
            ),
            3
        )
    }

    func testSelectsLargestLeadingPrefixWithExactOverflowWidth() {
        XCTAssertEqual(
            NativeProducedFilesLayout.shownCount(
                available: 156,
                chipWidths: [50, 60, 70],
                moreWidthsByHidden: [4: 30, 5: 30, 6: 30, 7: 30],
                totalCount: 7,
                gap: 8
            ),
            2,
            "two chips, the exact + 5 files label, and two gaps exactly fit"
        )
    }

    func testShowsAllCandidatesWhenNoOverflowLabelIsNeeded() {
        XCTAssertEqual(
            NativeProducedFilesLayout.shownCount(
                available: 190,
                chipWidths: [50, 60, 70],
                moreWidthsByHidden: [1: 30, 2: 30],
                totalCount: 3,
                gap: 8
            ),
            3
        )
    }
}
