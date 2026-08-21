import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeCompactionPresentationTests: XCTestCase {
    func testCompletedCompactionUsesOfficialCountSummaryAndRemainsExpandableWhenSummaryExists() {
        let compaction = node(summary: "Host summary", items: 4, tokens: 1_024)

        XCTAssertTrue(NativeCompactionPresentation.isExpandable(compaction))
        XCTAssertEqual(
            NativeCompactionPresentation.summary(compaction),
            OfficialUISpec.Text.compactionCompleted(items: 4, tokens: 1_024)
        )
    }

    func testSummaryOnlyCompactionUsesOfficialExpandCopy() {
        let compaction = node(summary: "Host summary", items: nil, tokens: nil)

        XCTAssertTrue(NativeCompactionPresentation.isExpandable(compaction))
        XCTAssertEqual(NativeCompactionPresentation.summary(compaction), OfficialUISpec.Text.compactionExpand)
    }

    func testMissingHostSummaryIsUnavailableAndCannotExpand() {
        let compaction = node(summary: nil, items: nil, tokens: nil)

        XCTAssertFalse(NativeCompactionPresentation.isExpandable(compaction))
        XCTAssertEqual(NativeCompactionPresentation.summary(compaction), OfficialUISpec.Text.compactionUnavailable)
    }

    private func node(summary: String?, items: Int?, tokens: Int?) -> CoreCompactionNode {
        .init(
            compactionID: "fixture-compaction",
            seq: 7,
            time: 7,
            summary: summary,
            summaryEventSeq: summary == nil ? nil : 6,
            shadowedItemCount: items,
            shadowedTokenCount: tokens
        )
    }
}
