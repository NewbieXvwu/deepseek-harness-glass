import Foundation

/// Payload-direct facade above `DSHClientTransport`. Feature modules own typed
/// request/response DTOs and never construct HTTP requests or wire envelopes.
struct DSHAPIClient: Sendable {
    let transport: DSHClientTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.transport = DSHClientTransport(baseURL: baseURL, session: session)
    }

    func call<Request: Encodable, Response: Decodable>(
        _ method: String,
        payload: Request,
        timeout: TimeInterval = 30
    ) async throws -> Response {
        let payloadData = try encoder.encode(payload)
        let wirePayload: JSONValue
        do {
            wirePayload = try decoder.decode(JSONValue.self, from: payloadData)
        } catch {
            throw DSHTransportError.decoding("Could not encode \(method) payload: \(error.localizedDescription)")
        }
        let envelope = try await transport.call(method: method, payload: wirePayload, timeout: timeout)
        switch envelope.result {
        case let .success(value):
            do {
                return try decoder.decode(Response.self, from: encoder.encode(value))
            } catch {
                throw DSHTransportError.decoding("Could not decode \(method) result: \(error.localizedDescription)")
            }
        case let .failure(error):
            throw error
        }
    }

    func hostDescribe() async throws -> HostDescribeResponse {
        try await call("host.describe", payload: EmptyPayload())
    }

    func sessionList() async throws -> SessionListResponse {
        try await call("session.list", payload: EmptyPayload())
    }

    /// Source: `sessions.schema.ts:sessionHistoryRequestSchema`.
    func sessionHistory(
        sessionID: String,
        beforeSeq: Int? = nil,
        maxMessages: Int? = nil
    ) async throws -> SessionHistoryResponse {
        try await call(
            "session.history",
            payload: SessionHistoryRequest(
                sessionId: sessionID,
                beforeSeq: beforeSeq,
                maxMessages: maxMessages
            )
        )
    }

    func workspaceList() async throws -> WorkspaceListResponse {
        try await call("workspace.list", payload: EmptyPayload())
    }

    /// Source: `sessions.schema.ts:sessionPromptRequestSchema`.
    func sessionPrompt(
        sessionID: String,
        content: [SessionPromptContent],
        mode: SessionPromptMode
    ) async throws -> SessionPromptResponse {
        try await call(
            "session.prompt",
            payload: SessionPromptRequest(
                sessionId: sessionID,
                mode: mode,
                content: content,
                clientTimeZone: TimeZone.current.identifier
            )
        )
    }

    /// Source: `sessions.schema.ts:sessionCancelRequestSchema`.
    func sessionCancel(sessionID: String) async throws -> SessionCancelResponse {
        try await call("session.cancel", payload: SessionCancelRequest(sessionId: sessionID))
    }

    /// Source: `sessions.schema.ts:sessionCreateRequestSchema`.
    func sessionCreate(workspaceID: String? = nil) async throws -> SessionCreateResponse {
        try await call("session.create", payload: SessionCreateRequest(workspaceId: workspaceID))
    }

    /// Source: `workspace.schema.ts:workspaceCreateRequestSchema`.
    func workspaceCreate(path: String) async throws -> WorkspaceCreateResponse {
        try await call("workspace.create", payload: WorkspaceCreateRequest(path: path))
    }

    func settingsDescribe() async throws -> SettingsDescribeResponse {
        try await call("settings.describe", payload: EmptyPayload())
    }

    /// Source: `rpc.ts:ClientResponse`; reply to an answerable mux ServerRequest
    /// by echoing its original rpcId to POST `/api/respond`.
    func respond(rpcID: String, result: RPCResult) async throws -> RPCReceipt {
        try await transport.respond(RPCClientResponse(rpcId: rpcID, result: result))
    }
}

struct EmptyPayload: Codable, Sendable {}

/// Source: `sessions.schema.ts:sessionHistoryRequestSchema`.
struct SessionHistoryRequest: Encodable, Sendable {
    let sessionId: String
    let beforeSeq: Int?
    let maxMessages: Int?
}

/// Source: `sessions.schema.ts:sessionHistoryValueSchema`.
struct SessionHistoryResponse: Decodable, Sendable {
    let events: [SessionHistoryEntryDTO]
    let hasMore: Bool
    let projections: SessionProjectionsDTO?
}

/// Source: `sessions.schema.ts:historyEntrySchema`.
struct SessionHistoryEntryDTO: Decodable, Sendable {
    let event: SessionEventDTO
    let view: ToolEventViewDTO?
}

/// Source: `sessions.schema.ts:sessionEventSchema`.
struct SessionEventDTO: Decodable, Sendable, Identifiable {
    let type: String
    let seq: Int
    let time: Double
    let data: JSONValue
    let sourceEventSeqs: [Int]?
    let ignorable: Bool?

    var id: Int { seq }
}

/// Source: `events.ts:ToolEventView` (merge-extensible presentation carrier).
struct ToolEventViewDTO: Decodable, Sendable {
    let `for`: String
    let view: JSONValue
}

/// Source: `sessions.schema.ts:sessionPromptRequestSchema`.
enum SessionPromptMode: String, Encodable, Sendable {
    case queue
    case steer
}

/// Source: `sessions.schema.ts:promptContentPartSchema`.
enum SessionPromptContent: Encodable, Sendable {
    case text(text: String)
    case image(mediaType: String, data: String, name: String?)

    private enum CodingKeys: String, CodingKey { case type, text, mediaType, data, name }
    private enum Kind: String, Encodable { case text, image }

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

/// Source: `sessions.schema.ts:sessionPromptRequestSchema`.
struct SessionPromptRequest: Encodable, Sendable {
    let sessionId: String
    let mode: SessionPromptMode
    let content: [SessionPromptContent]
    let clientTimeZone: String?
}

/// Source: `sessions.schema.ts:sessionPromptValueSchema`.
struct SessionPromptResponse: Decodable, Sendable {
    let accepted: Bool
}

/// Source: `sessions.schema.ts:sessionCancelRequestSchema`.
struct SessionCancelRequest: Encodable, Sendable {
    let sessionId: String
}

/// Source: `sessions.schema.ts:sessionCancelValueSchema`.
struct SessionCancelResponse: Decodable, Sendable {
    let accepted: Bool
}

/// Source: `sessions.schema.ts:sessionCreateRequestSchema`.
struct SessionCreateRequest: Encodable, Sendable {
    let workspaceId: String?
}

/// Source: `sessions.schema.ts:sessionCreateValueSchema`.
struct SessionCreateResponse: Decodable, Sendable {
    let sessionId: String
    let agentPreset: String?
}

/// Source: `workspace.schema.ts:workspaceCreateRequestSchema`.
struct WorkspaceCreateRequest: Encodable, Sendable {
    let path: String
}

/// Source: `workspace.schema.ts:workspaceCreateValueSchema`.
struct WorkspaceCreateResponse: Decodable, Sendable {
    let workspace: WorkspaceSummaryDTO
    let created: Bool
}

/// These intentionally retain only stable top-level fields needed by the first
/// native readiness/browser phases. Per-domain DTOs expand only with official
/// schema fixtures; unknown fields remain decodable through Codable defaults.
struct HostDescribeResponse: Decodable, Sendable {
    let canOpenPath: Bool?
    let directoryPicker: String?
}

struct SessionListResponse: Decodable, Sendable {
    let items: [SessionSummaryDTO]
}

/// Source: `sessions.schema.ts:sessionSummarySchema`.
struct SessionSummaryDTO: Decodable, Sendable, Identifiable {
    let sessionId: String
    let updatedAt: Double
    let running: Bool
    let blank: Bool
    /// Source: `dsh-client-runtime/client` SessionSummary.pendingInteraction.
    /// The Host omits it when no user response is pending.
    let pendingInteraction: String?
    let parentSessionId: String?
    let origin: String?
    let cwd: String?
    let agentPreset: String?
    let projections: SessionProjectionsDTO?

    /// Source: `session-title/src/types.ts:SessionProjectionMap.title`.
    var displayTitle: String? { projections?.values["title"]?.stringValue }

    var id: String { sessionId }
}

/// Source: `sessions.ts:SessionProjectionsBlock`. The projection registry is
/// merge-extensible; the native shell reads only the locked `title` value.
struct SessionProjectionsDTO: Decodable, Sendable {
    let asOfSeq: Int
    let values: [String: JSONValue]
}

/// Source: `workspace.schema.ts:workspaceListValueSchema`.
struct WorkspaceListResponse: Decodable, Sendable {
    let items: [WorkspaceSummaryDTO]
    let archivedSessionIds: [String]
}

/// Source: `workspace.schema.ts:workspaceViewSchema`.
struct WorkspaceSummaryDTO: Decodable, Sendable, Identifiable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionIds: [String]
    let createdAt: String
    let updatedAt: String

    var id: String { workspaceId }
}

struct SettingsDescribeResponse: Decodable, Sendable {
    let sections: [SettingsSectionDTO]?
}

struct SettingsSectionDTO: Decodable, Sendable, Identifiable {
    let ns: String
    let revision: Int?
    let hasDocument: Bool?

    var id: String { ns }
}
