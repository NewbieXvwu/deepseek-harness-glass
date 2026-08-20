import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Typed, renderer-safe aggregate of the official extension surfaces that do
/// not all originate from the durable conversation event window. This value is
/// deliberately a read-only projection: queue/jobs and interactions remain
/// Host ServerRequest snapshots, while todos/goals remain versioned projection
/// values. It never manufactures a value from local composer intent.
struct CoreSessionExtensionState: Equatable {
    /// `nil` denotes an absent, tombstoned, or malformed `todos` capability;
    /// an empty array is the Host's valid empty whole projection.
    let todos: [CoreTodoItem]?
    /// `nil` denotes an absent, tombstoned, or malformed `goal` projection.
    let goal: CoreGoalProjection?
    /// Complete transient Host snapshot. Empty means the Host explicitly has no
    /// queued/steering/context rows for the current subscription generation.
    let queuedMessages: [NativeSessionStore.QueuedMessage]
    /// Complete transient Host snapshot. Empty means no jobs for the current
    /// subscription generation, not an unobserved or locally inferred state.
    let backgroundJobs: [NativeSessionStore.BackgroundJob]
    /// Pending interaction states are mutually independent typed ServerRequest
    /// contracts. Their request identities remain available for single-answer
    /// fencing in the Feature layer.
    let pendingApproval: NativeSessionStore.PendingApproval?
    let pendingQuestion: NativeSessionStore.PendingQuestion?

    init(
        projections: SessionProjectionStore,
        sessionID: String,
        queuedMessages: [NativeSessionStore.QueuedMessage],
        backgroundJobs: [NativeSessionStore.BackgroundJob],
        pendingApproval: NativeSessionStore.PendingApproval?,
        pendingQuestion: NativeSessionStore.PendingQuestion?
    ) {
        todos = SessionTodoProjectionReader.value(from: projections, sessionID: sessionID)
        goal = SessionGoalProjectionReader.value(from: projections, sessionID: sessionID)
        self.queuedMessages = queuedMessages
        self.backgroundJobs = backgroundJobs
        self.pendingApproval = pendingApproval
        self.pendingQuestion = pendingQuestion
    }
}
