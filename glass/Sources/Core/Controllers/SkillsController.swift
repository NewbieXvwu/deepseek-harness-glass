import Foundation

protocol SkillsControllerAPI: Sendable {
    func list(sessionID: String) async throws -> RemoteSkillCatalog
}

struct RemoteSkillEntry: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let description: String
    let whenToUse: String?
    let modelInvocable: Bool

    var id: String { name }
}

struct RemoteSkillCatalog: Codable, Sendable, Equatable {
    let skills: [RemoteSkillEntry]
}

struct SkillsController: SkillsControllerAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func list(sessionID: String) async throws -> RemoteSkillCatalog {
        try await remote.call(
            RemoteProcedure(.skillsList),
            arguments: ListArguments(request: .init(sessionId: sessionID))
        )
    }

    private struct ListRequest: Codable, Sendable {
        let sessionId: String
    }

    private struct ListArguments: Codable, Sendable {
        let request: ListRequest
    }
}
