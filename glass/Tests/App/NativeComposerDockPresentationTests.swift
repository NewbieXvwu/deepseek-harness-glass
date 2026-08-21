import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeComposerDockPresentationTests: XCTestCase {
    func testHostProjectionDocksUseFixedTodoGoalQueueOrder() {
        XCTAssertEqual(
            NativeComposerDockPresentation.components(
                todos: [.init(id: "todo-1", text: "Host todo", status: .pending)],
                goal: .init(id: "goal-1", title: "Host goal", phase: .active),
                queuedMessages: [.init(id: "queue-1", content: [.text("Host queue")])],
                locallyClearedGoalID: nil,
                hasPendingTakeover: false
            ),
            [.todo, .goal, .queue]
        )
    }

    func testEmptyOrLocallyClearedHostProjectionDoesNotCreateDockPlaceholder() {
        XCTAssertEqual(
            NativeComposerDockPresentation.components(
                todos: [],
                goal: .init(id: "goal-1", title: "Host goal", phase: .active),
                queuedMessages: [],
                locallyClearedGoalID: "goal-1",
                hasPendingTakeover: false
            ),
            []
        )
    }

    func testPendingTakeoverHidesAllDocksUntilHostResolvesInteraction() {
        XCTAssertEqual(
            NativeComposerDockPresentation.components(
                todos: [.init(id: "todo-1", text: "Host todo", status: .pending)],
                goal: .init(id: "goal-1", title: "Host goal", phase: .active),
                queuedMessages: [.init(id: "queue-1", content: [.text("Host queue")])],
                locallyClearedGoalID: nil,
                hasPendingTakeover: true
            ),
            []
        )
    }
}
