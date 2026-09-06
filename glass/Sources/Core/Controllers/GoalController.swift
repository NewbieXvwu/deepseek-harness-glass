import Foundation

protocol GoalControllerAPI: Sendable {
    func edit(sessionID: String, ref: RemoteGoalRef, objective: String) async throws
    func pause(sessionID: String, ref: RemoteGoalRef) async throws
    func resume(sessionID: String, ref: RemoteGoalRef) async throws
    func clear(sessionID: String, ref: RemoteGoalRef) async throws
}

struct RemoteGoalRef: Codable, Sendable, Equatable {
    let id: String
    let revision: Int
}

struct GoalController: GoalControllerAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func edit(sessionID: String, ref: RemoteGoalRef, objective: String) async throws {
        let _: RemoteJSONValue = try await remote.call(
            RemoteProcedure(.goalsEdit),
            arguments: EditArguments(
                agentId: sessionID,
                ref: ref,
                request: .init(objective: objective)
            )
        )
    }

    func pause(sessionID: String, ref: RemoteGoalRef) async throws {
        try await mutate(.goalsPause, sessionID: sessionID, ref: ref)
    }

    func resume(sessionID: String, ref: RemoteGoalRef) async throws {
        try await mutate(.goalsResume, sessionID: sessionID, ref: ref)
    }

    func clear(sessionID: String, ref: RemoteGoalRef) async throws {
        try await mutate(.goalsClear, sessionID: sessionID, ref: ref)
    }

    private func mutate(_ endpoint: RemoteEndpoint, sessionID: String, ref: RemoteGoalRef) async throws {
        let _: RemoteJSONValue = try await remote.call(
            RemoteProcedure(endpoint),
            arguments: ReferenceArguments(agentId: sessionID, ref: ref)
        )
    }

    private struct EditRequest: Codable, Sendable { let objective: String }
    private struct EditArguments: Codable, Sendable {
        let agentId: String
        let ref: RemoteGoalRef
        let request: EditRequest
    }
    private struct ReferenceArguments: Codable, Sendable {
        let agentId: String
        let ref: RemoteGoalRef
    }
}
