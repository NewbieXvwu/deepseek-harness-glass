import Foundation

struct SubagentPromptIntent: Sendable, Equatable {
    let requestID: SessionRequestID
    let parentSessionID: String
    let childSessionID: String
    let content: [RemotePromptContentPart]
    let clientTimeZone: String?

    var request: RemoteSubagentPromptRequest {
        .init(
            requestId: requestID,
            parentSessionId: parentSessionID,
            childSessionId: childSessionID,
            content: content,
            clientTimeZone: clientTimeZone
        )
    }
}

enum AddressedSessionPromptIntent: Sendable, Equatable {
    case session(SessionPromptIntent)
    case subagent(SubagentPromptIntent)

    var requestID: SessionRequestID {
        switch self {
        case let .session(intent): intent.requestID
        case let .subagent(intent): intent.requestID
        }
    }
}

enum AddressedSessionCommandError: Error, Sendable, Equatable {
    case subagentControllerUnavailable
    case oneShotReadOnly
    case unsupportedSubagentPromptMode(RemoteSessionPromptMode)
    case unsupportedSubagentCommand
}

/// Routes mutations by the exact durable Session address. Ordinary Sessions use
/// the Session controller. Continuable direct children use the subagent owner
/// retained in their address. One-shot children remain read-only by contract.
struct AddressedSessionCommandService: Sendable {
    private let address: SessionAddress
    private let session: SessionCommandService
    private let subagents: (any SubagentControllerAPI)?

    init(
        address: SessionAddress,
        controller: any SessionControllerAPI,
        interactions: (any SessionInteractionResponder)? = nil,
        subagents: (any SubagentControllerAPI)? = nil
    ) {
        self.address = address
        self.session = SessionCommandService(controller: controller, interactions: interactions)
        self.subagents = subagents
    }

    func makePromptIntent(
        mode: RemoteSessionPromptMode,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) throws -> AddressedSessionPromptIntent {
        switch address {
        case let .session(sessionID):
            return .session(session.makePromptIntent(
                sessionID: sessionID,
                mode: mode,
                content: content,
                clientTimeZone: clientTimeZone
            ))

        case .subagent(_, _, .oneShot):
            throw AddressedSessionCommandError.oneShotReadOnly

        case let .subagent(parentSessionID, childSessionID, .continuable):
            guard mode == .queue else {
                throw AddressedSessionCommandError.unsupportedSubagentPromptMode(mode)
            }
            return .subagent(.init(
                requestID: .fresh(),
                parentSessionID: parentSessionID,
                childSessionID: childSessionID,
                content: content,
                clientTimeZone: clientTimeZone
            ))
        }
    }

    func submitPrompt(_ intent: AddressedSessionPromptIntent) async throws {
        switch intent {
        case let .session(intent):
            guard case .session = address else { throw AddressedSessionCommandError.unsupportedSubagentCommand }
            try await session.submitPrompt(intent)

        case let .subagent(intent):
            guard case let .subagent(parentSessionID, childSessionID, .continuable) = address,
                  intent.parentSessionID == parentSessionID,
                  intent.childSessionID == childSessionID
            else {
                throw AddressedSessionCommandError.unsupportedSubagentCommand
            }
            guard let subagents else { throw AddressedSessionCommandError.subagentControllerUnavailable }
            _ = try await subagents.prompt(intent.request)
        }
    }

    func retryPrompt(_ intent: AddressedSessionPromptIntent) async throws {
        try await submitPrompt(intent)
    }

    func cancel() async throws {
        switch address {
        case let .session(sessionID):
            try await session.cancel(sessionID: sessionID)

        case .subagent(_, _, .oneShot):
            throw AddressedSessionCommandError.oneShotReadOnly

        case let .subagent(parentSessionID, childSessionID, .continuable):
            guard let subagents else { throw AddressedSessionCommandError.subagentControllerUnavailable }
            _ = try await subagents.interrupt(
                parentSessionID: parentSessionID,
                childSessionID: childSessionID
            )
        }
    }

    func updateQueue(itemID: String, action: RemoteQueueAction) async throws {
        guard case let .session(sessionID) = address else {
            throw AddressedSessionCommandError.unsupportedSubagentCommand
        }
        try await session.updateQueue(sessionID: sessionID, itemID: itemID, action: action)
    }

    func answerApproval(eventID: String, allowOnce: Bool) async throws {
        try await session.answerApproval(eventID: eventID, allowOnce: allowOnce)
    }

    func answerQuestion(eventID: String, answers: [SessionQuestionCommandAnswer]) async throws {
        try await session.answerQuestion(eventID: eventID, answers: answers)
    }

    func cancelQuestion(eventID: String) async throws {
        try await session.cancelQuestion(eventID: eventID)
    }

    func selectModel(_ selection: RemoteModelSelection) async throws -> RemoteModelSelection {
        guard case let .session(sessionID) = address else {
            throw AddressedSessionCommandError.unsupportedSubagentCommand
        }
        return try await session.selectModel(sessionID: sessionID, selection: selection)
    }
}
