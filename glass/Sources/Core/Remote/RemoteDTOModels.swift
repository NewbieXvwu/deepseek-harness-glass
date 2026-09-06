import Foundation

/// Source: locked RC8 `host.openPath` request payload.
struct HostOpenPathRequest: Codable, Sendable {
    let path: String
}

/// Source: locked RC8 `host.openPath` success value.
struct HostOpenPathResponse: Decodable, Sendable {
    let opened: Bool
}

/// Source: `sessions.schema.ts:sessionHistoryRequestSchema`.
struct SessionHistoryRequest: Codable, Sendable {
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
}

/// Source: `sessions.schema.ts:sessionEventSchema`.
struct SessionEventDTO: Decodable, Sendable, Identifiable {
    let type: String
    let seq: Int
    let time: Double
    let data: JSONValue
    /// Present only on the official surface-producing user/message,
    /// assistant/message and tool/result variants. `"append"` is transcript
    /// material; a replacement object is model-only and may be a compaction
    /// checkpoint rather than a duplicate visible message.
    let surfaceOp: JSONValue?
    let sourceEventSeqs: [Int]?
    let ignorable: Bool?

    init(
        type: String,
        seq: Int,
        time: Double,
        data: JSONValue,
        surfaceOp: JSONValue? = nil,
        sourceEventSeqs: [Int]? = nil,
        ignorable: Bool? = nil
    ) {
        self.type = type
        self.seq = seq
        self.time = time
        self.data = data
        self.surfaceOp = surfaceOp
        self.sourceEventSeqs = sourceEventSeqs
        self.ignorable = ignorable
    }

    var id: Int { seq }
}

/// Source: `events.schema.ts:session/subscribed`. The stream's durable-history
/// watermark is `-1` for an empty log and is used to evict state from a prior
/// Host generation before its fresh transient baselines arrive.
struct SessionSubscribedDTO: Decodable, Sendable {
    let sessionId: String
    let lastSeq: Int
}

/// Source: `events.schema.ts:session/queue` and its `messageSchema`. Queue
/// messages are transient Host-owned inbox entries, never synthesised from the
/// durable transcript. Content remains JSON here so typed feature adapters can
/// render each official content-block kind without leaking wire dictionaries.
struct QueuedSessionMessageDTO: Decodable, Sendable {
    let id: String
    let role: String
    let content: [JSONValue]
    let source: JSONValue
}

enum SessionQueuePlacementDTO: String, Decodable, Sendable {
    case queued
    case steering
    case context
}

struct SessionQueueItemDTO: Decodable, Sendable {
    let id: String
    let placement: SessionQueuePlacementDTO
    let message: QueuedSessionMessageDTO
}

struct SessionQueueFrameDTO: Decodable, Sendable {
    let sessionId: String
    let items: [SessionQueueItemDTO]
}

/// Source: `jobs.schema.ts:taskViewSchema`; `kind` deliberately remains an
/// open string because plugins extend the registry's job vocabulary.
enum SessionJobStatusDTO: String, Decodable, Sendable {
    case running
    case stopping
    case completed
    case killed
    case failed
}

struct SessionJobDTO: Decodable, Sendable {
    let id: String
    let kind: String
    let label: String
    let status: SessionJobStatusDTO
    let detail: String?
    let startedAt: Int
    let finishedAt: Int?
}

struct SessionJobsFrameDTO: Decodable, Sendable {
    let sessionId: String
    let jobs: [SessionJobDTO]
}

/// Source: `sessions.schema.ts:sessionModelsRequestSchema`.
struct SessionModelsRequest: Codable, Sendable { let sessionId: String }

/// Source: `sessions.schema.ts:sessionModelsValueSchema`.
struct SessionModelsResponse: Decodable, Sendable {
    let current: SessionModelSelectionDTO
    let routable: Bool
    let groups: [SessionModelProviderGroupDTO]
    let failures: [SessionModelCatalogFailureDTO]
}

/// Source: RC8 `SessionAPI.selectModel` request. Omitting rather than nulling
/// `reasoningEffort` preserves the optional wire contract.
struct SessionSelectModelRequest: Codable, Sendable, Equatable {
    let sessionId: String
    let provider: String
    let model: String
    let reasoningEffort: String?
}

/// Source: RC8 `SessionAPI.selectModel` response.
struct SessionSelectModelResponse: Decodable, Sendable, Equatable {
    let selected: SessionModelSelectionDTO
}

struct SessionModelSelectionDTO: Codable, Sendable, Equatable {
    let provider: String
    let model: String
    let reasoningEffort: String?
}

struct SessionModelReasoningEffortDTO: Codable, Sendable {
    let id: String
    let name: String
    let description: String?
}

struct SessionModelReasoningDTO: Codable, Sendable {
    let efforts: [SessionModelReasoningEffortDTO]
    let defaultEffort: String?
}

struct SessionModelCatalogDTO: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let reasoning: SessionModelReasoningDTO?
}

struct SessionModelProviderGroupDTO: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let models: [SessionModelCatalogDTO]
}

struct SessionModelCatalogFailureDTO: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let message: String
}

/// Source: `sessions.schema.ts:sessionPromptRequestSchema`.
enum SessionPromptMode: String, Codable, Sendable, Equatable {
    case queue
    case steer
}

/// Source: `sessions.schema.ts:promptContentPartSchema`.
enum SessionPromptContent: Codable, Sendable, Equatable {
    case text(text: String)
    case image(mediaType: String, data: String, name: String?)

    private enum CodingKeys: String, CodingKey { case type, text, mediaType, data, name }
    private enum Kind: String, Codable { case text, image }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(text: try container.decode(String.self, forKey: .text))
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

/// Source: `sessions.schema.ts:sessionPromptRequestSchema`.
struct SessionPromptRequest: Codable, Sendable {
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
struct SessionCancelRequest: Codable, Sendable {
    let sessionId: String
}

/// Source: `sessions.schema.ts:sessionCancelValueSchema`.
struct SessionCancelResponse: Decodable, Sendable {
    let accepted: Bool
}

/// Source: `sessions.schema.ts:sessionUpdateQueueRequestSchema`.
enum SessionQueueAction: Codable, Sendable, Equatable {
    case edit(content: [SessionPromptContent])
    case remove
    case steer

    private enum CodingKeys: String, CodingKey { case kind, content }
    private enum Kind: String, Codable { case edit, remove, steer }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .edit: self = .edit(content: try container.decode([SessionPromptContent].self, forKey: .content))
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
        case .remove:
            try container.encode(Kind.remove, forKey: .kind)
        case .steer:
            try container.encode(Kind.steer, forKey: .kind)
        }
    }
}

/// Source: `sessions.schema.ts:sessionUpdateQueueRequestSchema`.
struct SessionUpdateQueueRequest: Codable, Sendable, Equatable {
    let sessionId: String
    let itemId: String
    let action: SessionQueueAction
}

/// Source: `sessions.schema.ts:sessionUpdateQueueValueSchema`.
struct SessionUpdateQueueResponse: Decodable, Sendable, Equatable {
    let accepted: Bool
}

/// Source: `sessions.schema.ts:sessionCreateRequestSchema`.
struct SessionCreateRequest: Codable, Sendable {
    let workspaceId: String?
    let cwd: String?
    let sessionId: String?
    let agentPreset: String?

    init(
        workspaceId: String? = nil,
        cwd: String? = nil,
        sessionId: String? = nil,
        agentPreset: String? = nil
    ) {
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.sessionId = sessionId
        self.agentPreset = agentPreset
    }
}

/// Source: `sessions.schema.ts:sessionCreateValueSchema`.
struct SessionCreateResponse: Decodable, Sendable {
    let sessionId: String
    let agentPreset: String?
}

/// Source: `workspace.schema.ts:workspaceCreateRequestSchema`.
struct WorkspaceCreateRequest: Codable, Sendable {
    let path: String
}

/// Source: `workspace.schema.ts:workspaceCreateValueSchema`.
struct WorkspaceCreateResponse: Decodable, Sendable {
    let workspace: WorkspaceSummaryDTO
    let created: Bool
}

/// Source: `sessions.schema.ts:sessionSearchRequestSchema`.
struct SessionSearchRequest: Codable, Sendable {
    let query: String
}

/// Source: `sessions.schema.ts:sessionSearchValueSchema`.
struct SessionSearchResponse: Decodable, Sendable {
    let items: [SessionSearchItemDTO]
    let hasMore: Bool
}

/// Source: `sessions.schema.ts:sessionSearchItemSchema`.
struct SessionSearchItemDTO: Decodable, Sendable, Identifiable, Equatable {
    let sessionId: String
    let snippet: String

    var id: String { sessionId }
}

/// Source: `sessions.schema.ts:sessionRenameRequestSchema`.
struct SessionRenameRequest: Codable, Sendable {
    let sessionId: String
    let title: String
}

/// Source: `sessions.schema.ts:sessionRenameValueSchema`.
struct SessionRenameResponse: Decodable, Sendable {
    let title: String
    let seq: Int
}

/// Source: `sessions.schema.ts:sessionForkRequestSchema`.
struct SessionForkRequest: Codable, Sendable {
    let sessionId: String
    let atSeq: Int?
}

/// Source: `sessions.schema.ts:sessionForkValueSchema`.
struct SessionForkResponse: Decodable, Sendable {
    let sessionId: String
}

/// Source: `workspace.schema.ts:workspaceRenameRequestSchema`.
struct WorkspaceRenameRequest: Codable, Sendable {
    let workspaceId: String
    let title: String
}

/// Source: `workspace.schema.ts:workspaceRenameValueSchema`.
struct WorkspaceRenameResponse: Decodable, Sendable {
    let workspace: WorkspaceSummaryDTO
}

/// Source: `workspace.schema.ts:workspaceDeleteRequestSchema`.
struct WorkspaceDeleteRequest: Codable, Sendable {
    let workspaceId: String
}

/// Source: `workspace.schema.ts:workspaceDeleteValueSchema`.
struct WorkspaceDeleteResponse: Decodable, Sendable {
    let deleted: Bool
}

/// Source: `workspace.schema.ts:workspaceInsertBeforeRequestSchema`.
struct WorkspaceInsertBeforeRequest: Codable, Sendable {
    let workspaceId: String
    let beforeWorkspaceId: String?
}

/// Source: `workspace.schema.ts:workspaceInsertBeforeValueSchema`.
struct WorkspaceInsertBeforeResponse: Decodable, Sendable {
    let workspaceIds: [String]
}

/// Source: `workspace.schema.ts:workspaceInsertSessionBeforeRequestSchema`.
struct WorkspaceInsertSessionBeforeRequest: Codable, Sendable {
    let workspaceId: String
    let sessionId: String
    let beforeSessionId: String?
}

/// Source: `workspace.schema.ts:workspaceInsertSessionBeforeValueSchema`.
struct WorkspaceInsertSessionBeforeResponse: Decodable, Sendable {
    let workspace: WorkspaceSummaryDTO
}

/// Source: `workspace.schema.ts:workspaceArchiveSessionRequestSchema`.
struct WorkspaceArchiveSessionRequest: Codable, Sendable {
    let sessionId: String
}

/// Source: `workspace.schema.ts:workspaceArchiveSessionValueSchema`.
struct WorkspaceArchiveSessionResponse: Decodable, Sendable {
    let archivedSessionIds: [String]
}

/// These intentionally retain only stable top-level fields needed by the first
/// native readiness/browser phases. Per-domain DTOs expand only with official
/// schema fixtures; unknown fields remain decodable through Codable defaults.
/// Source: `packages/host/apiproxy/src/api/host.schema.ts:hostDescribeValueSchema`.
/// RC8 makes the account home directory part of every Host description so native
/// displays can apply the same POSIX-only `~` abbreviation as the official UI.
struct HostDescribeResponse: Decodable, Sendable {
    let version: String
    let cwd: String
    let provider: String?
    let model: String?
    let attachedSessions: Int
    let home: String
    let canOpenPath: Bool
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
/// merge-extensible; native features decode only locked named values.
struct SessionProjectionsDTO: Decodable, Sendable {
    let asOfSeq: Int
    let values: [String: JSONValue]
}

/// Source: `packages/host/apiproxy/src/api/sessions.schema.ts:imageLimitsProjectionSchema`.
/// This Host-owned value is optional as a projection because attachment services
/// may be absent; every individual field is required whenever the key exists.
struct ImageAttachmentLimits: Decodable, Equatable, Sendable {
    let maxImageBytes: Int
    let maxImagesPerMessage: Int
    let maxMessageImageBytes: Int
    let maxImagePixels: Int
    let maxImageDimension: Int
    let mediaTypes: [String]
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

/// Source: `settings.schema.ts:settingsDescribeValueSchema`.
struct SettingsDescribeResponse: Decodable, Sendable {
    let writable: Bool
    let hasDocument: Bool
    let namespaces: [SettingsNamespaceDTO]
}

/// Source: `settings.ts:SettingsNamespaceView`.
struct SettingsNamespaceDTO: Codable, Sendable, Identifiable, Equatable {
    let ns: String
    let schema: JSONValue
    let value: JSONValue
    let base: JSONValue?
    let user: JSONValue?
    let applies: String
    let secrets: [SettingsSecretDTO]
    let revision: Int

    var id: String { ns }
}

/// Source: `settings.ts:SettingsSecretView`.
struct SettingsSecretDTO: Codable, Sendable, Equatable {
    let path: [String]
    let set: Bool
}

/// Source: `settings.schema.ts:settingsPathOpSchema`.
enum SettingsPathOperationDTO: Codable, Sendable, Equatable {
    case set(path: [String], value: JSONValue)
    case unset(path: [String])

    var path: [String] {
        switch self {
        case let .set(path, _), let .unset(path): return path
        }
    }

    private enum CodingKeys: String, CodingKey { case op, path, value }
    private enum Operation: String, Codable { case set, unset }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Operation.self, forKey: .op) {
        case .set:
            self = .set(
                path: try container.decode([String].self, forKey: .path),
                value: try container.decode(JSONValue.self, forKey: .value)
            )
        case .unset:
            self = .unset(path: try container.decode([String].self, forKey: .path))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .set(path, value):
            try container.encode(Operation.set, forKey: .op)
            try container.encode(path, forKey: .path)
            try container.encode(value, forKey: .value)
        case let .unset(path):
            try container.encode(Operation.unset, forKey: .op)
            try container.encode(path, forKey: .path)
        }
    }
}

/// Source: `settings.schema.ts:settingsMutateRequestSchema`.
struct SettingsMutateRequest: Codable, Sendable {
    let ns: String
    let ops: [SettingsPathOperationDTO]
    let expectedRevision: Int?
}
