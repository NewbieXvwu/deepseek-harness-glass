import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeComposerDockPresentationTests: XCTestCase {
    func testHostProjectionDocksUseFixedTodoGoalQueueStatsOrder() {
        XCTAssertEqual(
            NativeComposerDockPresentation.components(
                todos: [.init(content: "Host todo", status: .pending)],
                goal: goal(),
                queuedMessages: [queuedMessage()],
                chatNodes: [assistantNode()],
                locallyClearedGoalID: nil,
                hasPendingTakeover: false
            ),
            [.todo, .goal, .queue, .stats]
        )
    }

    func testEmptyOrLocallyClearedHostProjectionDoesNotCreateDockPlaceholder() {
        XCTAssertEqual(
            NativeComposerDockPresentation.components(
                todos: [],
                goal: goal(),
                queuedMessages: [],
                chatNodes: [],
                locallyClearedGoalID: "goal-1",
                hasPendingTakeover: false
            ),
            []
        )
    }

    func testPendingTakeoverHidesAllDocksIncludingStatsUntilHostResolvesInteraction() {
        XCTAssertEqual(
            NativeComposerDockPresentation.components(
                todos: [.init(content: "Host todo", status: .pending)],
                goal: goal(),
                queuedMessages: [queuedMessage()],
                chatNodes: [assistantNode()],
                locallyClearedGoalID: nil,
                hasPendingTakeover: true
            ),
            []
        )
    }

    private func goal() -> CoreGoalProjection {
        guard let goal = CoreGoalProjection(projection: .object([
            "goal": .object([
                "id": .string("goal-1"),
                "revision": .number(1),
                "objective": .string("Host goal"),
                "phase": .string("active"),
                "maxGoalRounds": .number(3),
            ]),
            "roundsStarted": .number(0),
            "createdAt": .number(1),
            "updatedAt": .number(1),
        ])) else {
            fatalError("goal fixture must satisfy the Host projection contract")
        }
        return goal
    }

    private func queuedMessage() -> NativeSessionStore.QueuedMessage {
        .init(
            id: "queue-1",
            messageID: "queue-1",
            placement: .queued,
            role: "user",
            content: [.string("Host queue")],
            source: .object([:]),
            preview: "Host queue",
            text: "Host queue"
        )
    }

    private func assistantNode() -> ConversationViewNode {
        .init(
            key: "stats-assistant",
            kind: "assistant-step",
            id: "1:1",
            target: "chat",
            data: CoreAssistantNode(
                status: .settled,
                turn: 1,
                step: 1,
                seq: 1,
                time: 1,
                messageID: "stats-assistant",
                blocks: [],
                firstTokenTime: nil,
                completedTime: 1,
                usage: nil
            )
        )
    }
}
