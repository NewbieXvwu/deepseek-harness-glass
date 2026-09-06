import Foundation

struct SessionPromptIntent: Sendable, Equatable {
    let requestID: SessionRequestID
    let sessionID: String
    let mode: RemoteSessionPromptMode
}

struct SessionCommandService: Sendable {
    private let controller: any SessionControllerAPI

    init(controller: any SessionControllerAPI) {
        self.controller = controller
    }

    func prompt(
        sessionID: String,
        mode: RemoteSessionPromptMode,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) async throws -> SessionPromptIntent {
        let requestID = SessionRequestID.fresh()
        let request = RemoteSessionPromptRequest(
            requestId: requestID,
            sessionId: sessionID,
            mode: mode,
            content: content,
            clientTimeZone: clientTimeZone
        )
        _ = try await controller.prompt(request)
        return .init(requestID: requestID, sessionID: sessionID, mode: mode)
    }

    func retryPrompt(
        intent: SessionPromptIntent,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) async throws {
        let request = RemoteSessionPromptRequest(
            requestId: intent.requestID,
            sessionId: intent.sessionID,
            mode: intent.mode,
            content: content,
            clientTimeZone: clientTimeZone
        )
        _ = try await controller.prompt(request)
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
