import Foundation

protocol CommandsControllerAPI: Sendable {
    func list(sessionID: String) async throws -> [RemoteCommandDescriptor]
    func execute(
        sessionID: String,
        line: String,
        images: [RemoteEncodedImageAttachment]
    ) async throws -> RemoteCommandExecution?
}

struct RemoteCommandInputDescriptor: Codable, Sendable, Equatable {
    let hint: String
    let images: Bool?
}

struct RemoteCommandDescriptor: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let description: String
    let input: RemoteCommandInputDescriptor?

    var id: String { name }
}

struct RemoteEncodedImageAttachment: Codable, Sendable, Equatable {
    let mediaType: String
    let data: String
    let name: String?
}

enum RemoteCommandResult: Codable, Sendable, Equatable {
    case success(text: String?, sourceEventSeq: SessionSeq?)
    case error(text: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case sourceEventSeq
    }

    private enum Kind: String, Codable {
        case success
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .success:
            self = .success(
                text: try container.decodeIfPresent(String.self, forKey: .text),
                sourceEventSeq: try container.decodeIfPresent(SessionSeq.self, forKey: .sourceEventSeq)
            )
        case .error:
            self = .error(text: try container.decode(String.self, forKey: .text))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .success(text, sourceEventSeq):
            try container.encode(Kind.success, forKey: .kind)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(sourceEventSeq, forKey: .sourceEventSeq)
        case let .error(text):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(text, forKey: .text)
        }
    }
}

struct RemoteCommandExecution: Codable, Sendable, Equatable {
    let commandId: String
    let result: RemoteCommandResult
}

struct CommandsController: CommandsControllerAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func list(sessionID: String) async throws -> [RemoteCommandDescriptor] {
        try await remote.call(
            RemoteProcedure(.commandsList),
            arguments: ListArguments(agentId: sessionID)
        )
    }

    func execute(
        sessionID: String,
        line: String,
        images: [RemoteEncodedImageAttachment] = []
    ) async throws -> RemoteCommandExecution? {
        try await remote.call(
            RemoteProcedure(.commandsExecute),
            arguments: ExecuteArguments(agentId: sessionID, line: line, images: images)
        )
    }

    private struct ListArguments: Codable, Sendable {
        let agentId: String
    }

    private struct ExecuteArguments: Codable, Sendable {
        let agentId: String
        let line: String
        let images: [RemoteEncodedImageAttachment]
    }
}
