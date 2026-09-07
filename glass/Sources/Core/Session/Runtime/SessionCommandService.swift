import Foundation

struct SessionPromptIntent: Sendable, Equatable {
    let requestID: SessionRequestID
    let sessionID: String
    let mode: RemoteSessionPromptMode
    let content: [RemotePromptContentPart]
    let clientTimeZone: String?

    var request: RemoteSessionPromptRequest {
        .init(
            requestId: requestID,
            sessionId: sessionID,
            mode: mode,
            content: content,
            clientTimeZone: clientTimeZone
        )
    }
}

struct SessionCommandService: Sendable {
    private let controller: any SessionControllerAPI

    init(controller: any SessionControllerAPI) {
        self.controller = controller
    }

    /// Creates the domain identity at the user-command boundary. The returned
    /// value owns the exact request payload so an idempotent retry cannot reuse
    /// one request id with edited content.
    func makePromptIntent(
        sessionID: String,
        mode: RemoteSessionPromptMode,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) -> SessionPromptIntent {
        .init(
            requestID: .fresh(),
            sessionID: sessionID,
            mode: mode,
            content: content,
            clientTimeZone: clientTimeZone
        )
    }

    /// Submits one already-identified user intent. A retry submits this exact
    /// value again and therefore preserves both request identity and payload.
    func submitPrompt(_ intent: SessionPromptIntent) async throws {
        _ = try await controller.prompt(intent.request)
    }

    /// Convenience for command callers that do not expose a retry affordance.
    /// Interactive composer code should create and retain the intent before
    /// awaiting this mutation so a transport failure keeps the same identity.
    func prompt(
        sessionID: String,
        mode: RemoteSessionPromptMode,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) async throws -> SessionPromptIntent {
        let intent = makePromptIntent(
            sessionID: sessionID,
            mode: mode,
            content: content,
            clientTimeZone: clientTimeZone
        )
        try await submitPrompt(intent)
        return intent
    }

    func retryPrompt(_ intent: SessionPromptIntent) async throws {
        try await submitPrompt(intent)
    }

    func cancel(sessionID: String) async throws {
        _ = try await controller.cancel(sessionID: sessionID)
    }

    func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws {
        _ = try await controller.updateQueue(sessionID: sessionID, itemID: itemID, action: action)
    }

    func selectModel(sessionID: String, selection: RemoteModelSelection) async throws -> RemoteModelSelection {
        try await controller.selectModel(sessionID: sessionID, selection: selection).selected
    }
}
