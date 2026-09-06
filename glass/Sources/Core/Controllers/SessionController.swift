import Foundation

protocol SessionControllerAPI: Sendable {
    func list() async throws -> RemoteSessionListValue
    func search(query: String) async throws -> RemoteSessionSearchValue
    func create(_ request: RemoteSessionCreateRequest) async throws -> RemoteSessionCreateValue
    func rename(sessionID: String, title: String) async throws -> RemoteSessionRenameValue
    func fork(sessionID: String, atSeq: SessionSeq?) async throws -> RemoteSessionForkValue
    func selectModel(sessionID: String, selection: RemoteModelSelection) async throws -> RemoteSessionSelectModelValue
    func modelCatalog() async throws -> RemoteModelCatalog
    func canOpenWorkspacePath() async throws -> Bool
    func openWorkspacePath(_ path: String) async throws -> RemoteSessionOpenWorkspacePathValue
    func prompt(_ request: RemoteSessionPromptRequest) async throws -> RemoteSessionAcceptedValue
    func cancel(sessionID: String) async throws -> RemoteSessionAcceptedValue
    func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws -> RemoteSessionAcceptedValue
    func page(_ request: RemoteSessionPageRequest) async throws -> RemoteSessionPageValue
    func follow(_ request: RemoteSessionFollowRequest) async throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error>
    func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error>
}

struct RemoteSessionSummary: Codable, Sendable, Equatable, Identifiable {
    let sessionId: String
    let updatedAt: Int64
    let running: Bool
    let blank: Bool
    let parentSessionId: String?
    let origin: String?
    let cwd: String?
    let projections: RemoteJSONValue?

    var id: String { sessionId }
}

struct RemoteSessionListValue: Codable, Sendable, Equatable {
    let items: [RemoteSessionSummary]
}

struct RemoteSessionSearchItem: Codable, Sendable, Equatable, Identifiable {
    let sessionId: String
    let snippet: String
    var id: String { sessionId }
}

struct RemoteSessionSearchValue: Codable, Sendable, Equatable {
    let items: [RemoteSessionSearchItem]
    let hasMore: Bool
}

struct RemoteSessionCreateRequest: Codable, Sendable, Equatable {
    let workspaceId: String?
    let cwd: String?
    let sessionId: String?
    let agentPreset: String?

    init(workspaceId: String? = nil, cwd: String? = nil, sessionId: String? = nil, agentPreset: String? = nil) {
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.sessionId = sessionId
        self.agentPreset = agentPreset
    }
}

struct RemoteSessionCreateValue: Codable, Sendable, Equatable {
    let sessionId: String
    let agentPreset: String?
}

struct RemoteSessionRenameValue: Codable, Sendable, Equatable {
    let title: String
    let seq: SessionSeq
}

struct RemoteSessionForkValue: Codable, Sendable, Equatable {
    let sessionId: String
}

struct RemoteModelSelection: Codable, Sendable, Equatable {
    let provider: String
    let model: String
    let reasoningEffort: String?

    init(provider: String, model: String, reasoningEffort: String? = nil) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

struct RemoteSessionSelectModelValue: Codable, Sendable, Equatable {
    let selected: RemoteModelSelection
}

struct RemoteModelReasoningEffort: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String?
}

struct RemoteModelReasoning: Codable, Sendable, Equatable {
    let efforts: [RemoteModelReasoningEffort]
    let defaultEffort: String?
}

struct RemoteModelCatalogModel: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let reasoning: RemoteModelReasoning?
}

struct RemoteModelProviderGroup: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let models: [RemoteModelCatalogModel]
}

struct RemoteModelCatalogFailure: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let message: String
}

struct RemoteModelCatalog: Codable, Sendable, Equatable {
    let `default`: RemoteModelSelection
    let routableProviders: [String]
    let groups: [RemoteModelProviderGroup]
    let failures: [RemoteModelCatalogFailure]
}

enum RemoteSessionPromptMode: String, Codable, Sendable { case queue, steer }

enum RemotePromptContentPart: Codable, Sendable, Equatable {
    case text(String)
    case image(mediaType: String, data: String, name: String?)

    private enum CodingKeys: String, CodingKey { case type, text, mediaType, data, name }
    private enum Kind: String, Codable { case text, image }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(
                mediaType: try container.decode(String.self, forKey: .mediaType),
                data: try container.decode(String.self, forKey: .data),
                name: try container.decodeIfPresent(String.self, forKey: .name)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(mediaType, data, name):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(mediaType, forKey: .mediaType)
            try container.encode(data, forKey: .data)
            try container.encodeIfPresent(name, forKey: .name)
        }
    }
}

struct RemoteSessionPromptRequest: Codable, Sendable, Equatable {
    let requestId: SessionRequestID
    let sessionId: String
    let mode: RemoteSessionPromptMode
    let content: [RemotePromptContentPart]
    let clientTimeZone: String?

    init(
        requestId: SessionRequestID,
        sessionId: String,
        mode: RemoteSessionPromptMode,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) {
        self.requestId = requestId
        self.sessionId = sessionId
        self.mode = mode
        self.content = content
        self.clientTimeZone = clientTimeZone
    }
}

enum RemoteQueueAction: Codable, Sendable, Equatable {
    case edit(content: [RemoteJSONValue])
    case remove
    case steer

    private enum CodingKeys: String, CodingKey { case kind, content }
    private enum Kind: String, Codable { case edit, remove, steer }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .edit: self = .edit(content: try container.decode([RemoteJSONValue].self, forKey: .content))
        case .remove: self = .remove
        case .steer: self = .steer
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .edit(content):
            try container.encode(Kind.edit, forKey: .kind)
            try container.encode(content, forKey: .content)
        case .remove: try container.encode(Kind.remove, forKey: .kind)
        case .steer: try container.encode(Kind.steer, forKey: .kind)
        }
    }
}

struct RemoteSessionAcceptedValue: Codable, Sendable, Equatable {
    let accepted: Bool
}

struct RemoteSessionOpenWorkspacePathValue: Codable, Sendable, Equatable {
    let opened: Bool
}

struct RemoteSessionPageRequest: Codable, Sendable, Equatable {
    let address: SessionAddress
    let throughSeq: SessionSeq
    let beforeSeq: SessionLogOffset?
    let maxMessages: Int?

    init(address: SessionAddress, throughSeq: SessionSeq, beforeSeq: SessionLogOffset? = nil, maxMessages: Int? = nil) {
        self.address = address
        self.throughSeq = throughSeq
        self.beforeSeq = beforeSeq
        self.maxMessages = maxMessages
    }
}

struct RemoteSessionFollowRequest: Codable, Sendable, Equatable {
    let address: SessionAddress
    let maxMessages: Int?

    init(address: SessionAddress, maxMessages: Int? = nil) {
        self.address = address
        self.maxMessages = maxMessages
    }
}

struct SessionController: SessionControllerAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func list() async throws -> RemoteSessionListValue {
        try await remote.call(
            RemoteProcedure(.sessionList),
            arguments: ListArguments(_request: ListRequest())
        )
    }

    func search(query: String) async throws -> RemoteSessionSearchValue {
        try await remote.call(
            RemoteProcedure(.sessionSearch),
            arguments: SearchArguments(request: SearchRequest(query: query))
        )
    }

    func create(_ request: RemoteSessionCreateRequest) async throws -> RemoteSessionCreateValue {
        try await remote.call(
            RemoteProcedure(.sessionCreate),
            arguments: CreateArguments(request: request)
        )
    }

    func rename(sessionID: String, title: String) async throws -> RemoteSessionRenameValue {
        try await remote.call(
            RemoteProcedure(.sessionRename),
            arguments: RenameArguments(request: .init(sessionId: sessionID, title: title))
        )
    }

    func fork(sessionID: String, atSeq: SessionSeq? = nil) async throws -> RemoteSessionForkValue {
        try await remote.call(
            RemoteProcedure(.sessionFork),
            arguments: ForkArguments(request: .init(sessionId: sessionID, atSeq: atSeq))
        )
    }

    func selectModel(sessionID: String, selection: RemoteModelSelection) async throws -> RemoteSessionSelectModelValue {
        try await remote.call(
            RemoteProcedure(.sessionSelectModel),
            arguments: SelectModelArguments(request: .init(
                sessionId: sessionID,
                provider: selection.provider,
                model: selection.model,
                reasoningEffort: selection.reasoningEffort
            ))
        )
    }

    func modelCatalog() async throws -> RemoteModelCatalog {
        try await remote.call(RemoteProcedure(.sessionModelCatalog), arguments: EmptyArguments())
    }

    func canOpenWorkspacePath() async throws -> Bool {
        try await remote.call(RemoteProcedure(.sessionCanOpenWorkspacePath), arguments: EmptyArguments())
    }

    func openWorkspacePath(_ path: String) async throws -> RemoteSessionOpenWorkspacePathValue {
        try await remote.call(
            RemoteProcedure(.sessionOpenWorkspacePath),
            arguments: OpenWorkspacePathArguments(request: .init(path: path))
        )
    }

    func prompt(_ request: RemoteSessionPromptRequest) async throws -> RemoteSessionAcceptedValue {
        try await remote.call(RemoteProcedure(.sessionPrompt), arguments: PromptArguments(request: request))
    }

    func cancel(sessionID: String) async throws -> RemoteSessionAcceptedValue {
        try await remote.call(
            RemoteProcedure(.sessionCancel),
            arguments: CancelArguments(request: .init(sessionId: sessionID))
        )
    }

    func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws -> RemoteSessionAcceptedValue {
        try await remote.call(
            RemoteProcedure(.sessionUpdateQueue),
            arguments: UpdateQueueArguments(request: .init(sessionId: sessionID, itemId: itemID, action: action))
        )
    }

    func page(_ request: RemoteSessionPageRequest) async throws -> RemoteSessionPageValue {
        try await remote.call(
            RemoteProcedure(.sessionPage),
            arguments: PageArguments(request: request)
        )
    }

    func follow(_ request: RemoteSessionFollowRequest) async throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error> {
        try await remote.stream(
            RemoteStreamProcedure(.sessionFollow),
            arguments: FollowArguments(request: request)
        )
    }

    func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error> {
        try await remote.stream(RemoteStreamProcedure(.sessionControl), arguments: EmptyArguments())
    }

    private struct ListRequest: Codable, Sendable {}
    private struct ListArguments: Codable, Sendable {
        let _request: ListRequest
    }
    private struct SearchRequest: Codable, Sendable { let query: String }
    private struct SearchArguments: Codable, Sendable { let request: SearchRequest }
    private struct CreateArguments: Codable, Sendable { let request: RemoteSessionCreateRequest }
    private struct RenameRequest: Codable, Sendable { let sessionId: String; let title: String }
    private struct RenameArguments: Codable, Sendable { let request: RenameRequest }
    private struct ForkRequest: Codable, Sendable { let sessionId: String; let atSeq: SessionSeq? }
    private struct ForkArguments: Codable, Sendable { let request: ForkRequest }
    private struct SelectModelRequest: Codable, Sendable {
        let sessionId: String
        let provider: String
        let model: String
        let reasoningEffort: String?
    }
    private struct SelectModelArguments: Codable, Sendable { let request: SelectModelRequest }
    private struct OpenWorkspacePathRequest: Codable, Sendable { let path: String }
    private struct OpenWorkspacePathArguments: Codable, Sendable { let request: OpenWorkspacePathRequest }
    private struct PromptArguments: Codable, Sendable { let request: RemoteSessionPromptRequest }
    private struct CancelRequest: Codable, Sendable { let sessionId: String }
    private struct CancelArguments: Codable, Sendable { let request: CancelRequest }
    private struct UpdateQueueRequest: Codable, Sendable {
        let sessionId: String
        let itemId: String
        let action: RemoteQueueAction
    }
    private struct UpdateQueueArguments: Codable, Sendable { let request: UpdateQueueRequest }
    private struct PageArguments: Codable, Sendable { let request: RemoteSessionPageRequest }
    private struct FollowArguments: Codable, Sendable { let request: RemoteSessionFollowRequest }
    private struct EmptyArguments: Codable, Sendable {}
}
