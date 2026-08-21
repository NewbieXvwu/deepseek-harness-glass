import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeComposerDockPresentationTests: XCTestCase {
    func testHostProjectionDocksUseFixedTodoGoalQueueStatsOrder() {
        XCTAssertEqual(
            NativeComposerDockPresentation.components(
                todos: [.init(id: "todo-1", text: "Host todo", status: .pending)],
                goal: .init(id: "goal-1", title: "Host goal", phase: .active),
                queuedMessages: [.init(id: "queue-1", content: [.text("Host queue")])],
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
                goal: .init(id: "goal-1", title: "Host goal", phase: .active),
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
                todos: [.init(id: "todo-1", text: "Host todo", status: .pending)],
                goal: .init(id: "goal-1", title: "Host goal", phase: .active),
                queuedMessages: [.init(id: "queue-1", content: [.text("Host queue")])],
                chatNodes: [assistantNode()],
                locallyClearedGoalID: nil,
                hasPendingTakeover: true
            ),
            []
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
