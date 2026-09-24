import Foundation
import XCTest

@testable import GlassCore

final class RemoteInteractionProjectorTests: XCTestCase {
    func testProjectsApprovalWaterfallWithEventIdentityAndSessionScope() {
        let update = RemoteInteractionProjector.project(.waterfall(
            event: "approval/request",
            eventID: "evt-approval",
            agentID: "session-alpha",
            request: [
                "toolName": .string("shell"),
                "callId": .string("call-1"),
                "reason": .string("needs confirmation")
            ]
        ))

        XCTAssertEqual(update, .approval(.init(
            eventID: "evt-approval",
            sessionID: "session-alpha",
            toolName: "shell",
            callID: "call-1",
            reason: "needs confirmation"
        )))
    }

    func testProjectsQuestionWaterfallIncludingPlanReviewAndMultiSelect() {
        let update = RemoteInteractionProjector.project(.waterfall(
            event: "user-questions/request",
            eventID: "evt-question",
            agentID: "session-beta",
            request: [
                "questions": .array([
                    .object([
                        "id": .string("plan"),
                        "question": .string("Approve this plan?"),
                        "header": .string("Plan review"),
                        "options": .array([
                            .object(["label": .string("Approve")]),
                            .object(["label": .string("Revise"), "description": .string("Request changes")])
                        ]),
                        "multiSelect": .bool(true),
                        "intent": .object([
                            "kind": .string("plan-review"),
                            "approve": .string("Approve")
                        ])
                    ])
                ])
            ]
        ))

        guard case let .question(question) = update else {
            return XCTFail("expected question waterfall")
        }
        XCTAssertEqual(question.eventID, "evt-question")
        XCTAssertEqual(question.sessionID, "session-beta")
        XCTAssertEqual(question.questions.count, 1)
        XCTAssertEqual(question.questions[0].options.map(\.label), ["Approve", "Revise"])
        XCTAssertTrue(question.questions[0].multiSelect)
        XCTAssertEqual(question.questions[0].intent, .planReview(approve: "Approve"))
    }

    func testRejectsMalformedQuestionBatchAndProjectsCancellation() {
        XCTAssertNil(RemoteInteractionProjector.project(.waterfall(
            event: "user-questions/request",
            eventID: "evt-bad",
            agentID: "session",
            request: ["questions": .array([.object(["id": .string("missing-question")])])]
        )))
        XCTAssertEqual(
            RemoteInteractionProjector.project(.cancel(eventID: "evt-cancel")),
            .cancelled(eventID: "evt-cancel")
        )
    }

    func testEventResultArgumentsEncodeOfficialOutcomeShapes() throws {
        let answer = RemoteEventResultArguments(
            clientId: "client-1",
            eventId: "evt-question",
            outcome: .result(.object([
                "answers": .array([
                    .object([
                        "id": .string("q1"),
                        "selected": .array([.string("A")])
                    ])
                ])
            ]))
        )
        let answerObject = try jsonObject(answer)
        XCTAssertEqual(answerObject["clientId"] as? String, "client-1")
        XCTAssertEqual(answerObject["eventId"] as? String, "evt-question")
        let answerOutcome = try XCTUnwrap(answerObject["outcome"] as? [String: Any])
        XCTAssertEqual(answerOutcome["kind"] as? String, "result")
        XCTAssertNotNil(answerOutcome["value"])

        let cancellation = RemoteEventResultArguments(
            clientId: "client-1",
            eventId: "evt-question",
            outcome: .rejected(.init(
                name: "UserQuestionError",
                message: "the user cancelled ask_user_question",
                code: "ASK_CANCELLED"
            ))
        )
        let cancellationObject = try jsonObject(cancellation)
        let cancellationOutcome = try XCTUnwrap(cancellationObject["outcome"] as? [String: Any])
        XCTAssertEqual(cancellationOutcome["kind"] as? String, "rejected")
        let error = try XCTUnwrap(cancellationOutcome["error"] as? [String: Any])
        XCTAssertEqual(error["name"] as? String, "UserQuestionError")
        XCTAssertEqual(error["code"] as? String, "ASK_CANCELLED")
    }

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
