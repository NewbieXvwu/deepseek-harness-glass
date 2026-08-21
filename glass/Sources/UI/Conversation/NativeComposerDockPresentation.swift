#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// The fixed native dock ordering is computed from Host projections only.  A
/// pending takeover replaces the complete composer dock, rather than leaving
/// stale goals, todos, or queued prompts visible underneath an interaction.
enum NativeComposerDockPresentation {
    enum Component: String, Equatable {
        case todo
        case goal
        case queue
    }

    static func components(
        todos: [CoreTodoItem]?,
        goal: CoreGoalProjection?,
        queuedMessages: [NativeSessionStore.QueuedMessage],
        locallyClearedGoalID: String?,
        hasPendingTakeover: Bool
    ) -> [Component] {
        guard !hasPendingTakeover else { return [] }
        var result: [Component] = []
        if NativeTodoDockPresentation.isVisible(todos) { result.append(.todo) }
        if NativeGoalDockPresentation.isVisible(goal, locallyClearedGoalID: locallyClearedGoalID) { result.append(.goal) }
        if !NativeQueueDockPresentation.queuedRows(queuedMessages).isEmpty { result.append(.queue) }
        return result
    }
}
