import XCTest

@testable import GlassUI

final class NativeTranscriptTailPresentationTests: XCTestCase {
    func testHostRunningControlsFixedStatusVisibilityAndScrollAnchor() {
        XCTAssertTrue(NativeTranscriptTailPresentation.showsRunningStatus(isRunning: true))
        XCTAssertEqual(
            NativeTranscriptTailPresentation.scrollTarget(isRunning: true, durableTailID: "assistant-row"),
            NativeTranscriptTailPresentation.runningStatusID
        )
    }

    func testSettledTurnUsesOnlyDurableTailAndEmptyTranscriptHasNoTarget() {
        XCTAssertFalse(NativeTranscriptTailPresentation.showsRunningStatus(isRunning: false))
        XCTAssertEqual(
            NativeTranscriptTailPresentation.scrollTarget(isRunning: false, durableTailID: "assistant-row"),
            "assistant-row"
        )
        XCTAssertNil(NativeTranscriptTailPresentation.scrollTarget(isRunning: false, durableTailID: nil))
    }
}
