import XCTest

@testable import GlassUI

final class NativeTranscriptTailPresentationTests: XCTestCase {
    func testHostRunningControlsFixedStatusVisibilityAndScrollAnchor() {
        XCTAssertEqual(
            NativeTranscriptTailPresentation.scrollTarget(isRunning: true, durableTailID: "assistant-row"),
            NativeTranscriptTailPresentation.runningStatusID
        )
    }

    func testSettledTurnUsesOnlyDurableTailAndEmptyTranscriptHasNoTarget() {
        XCTAssertEqual(
            NativeTranscriptTailPresentation.scrollTarget(isRunning: false, durableTailID: "assistant-row"),
            "assistant-row"
        )
        XCTAssertNil(NativeTranscriptTailPresentation.scrollTarget(isRunning: false, durableTailID: nil))
    }
}
