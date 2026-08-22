import XCTest

@testable import GlassCore

final class NativeToolAskQuestionPresentationTests: XCTestCase {
    func testProjectsWaitingCancelledAndAbortedVerdictsBeforeGenericResult() throws {
        XCTAssertEqual(
            NativeToolAskQuestionPresentation.resolve(
                toolName: "ask_user_question", isRunning: true, isCompleted: false, errorCode: nil, textOutput: nil
            ),
            .init(summary: .waiting, forcesStoppedState: false)
        )
        XCTAssertEqual(
            NativeToolAskQuestionPresentation.resolve(
                toolName: "ask_user_question", isRunning: false, isCompleted: false, errorCode: "ASK_CANCELLED", textOutput: #"{"answers":[]}"#
            ),
            .init(summary: .cancelled, forcesStoppedState: false)
        )
        XCTAssertEqual(
            NativeToolAskQuestionPresentation.resolve(
                toolName: "ask_user_question", isRunning: false, isCompleted: false, errorCode: "ASK_ABORTED", textOutput: #"{"answers":[]}"#
            ),
            .init(summary: .interrupted, forcesStoppedState: true)
        )
    }

    func testCountsSelectedAndCustomAnswersFromSettledTextResult() throws {
        let presentation = try XCTUnwrap(NativeToolAskQuestionPresentation.resolve(
            toolName: "ask_user_question",
            isRunning: false,
            isCompleted: true,
            errorCode: nil,
            textOutput: #"{"answers":[{"selected":["A"]},{"custom":"why"},{"selected":[]},{"custom":""}]}"#
        ))
        XCTAssertEqual(presentation.summary, .answered(answered: 2, total: 4))
        XCTAssertFalse(presentation.forcesStoppedState)
    }

    func testRetainsGenericFallbackForUnknownOrMalformedResults() {
        XCTAssertNil(NativeToolAskQuestionPresentation.resolve(
            toolName: "fx_ask_user_question", isRunning: false, isCompleted: true, errorCode: nil, textOutput: #"{"answers":[]}"#
        ))
        XCTAssertEqual(
            NativeToolAskQuestionPresentation.resolve(
                toolName: "ask_user_question", isRunning: false, isCompleted: true, errorCode: nil, textOutput: "not JSON"
            )?.summary,
            .generic
        )
        XCTAssertEqual(
            NativeToolAskQuestionPresentation.resolve(
                toolName: "ask_user_question", isRunning: false, isCompleted: true, errorCode: nil, textOutput: #"{"answers":[null]}"#
            )?.summary,
            .generic
        )
    }
}
