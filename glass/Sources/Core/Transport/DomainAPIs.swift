import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// The sole Core composition root exposed to native Feature/UI modules after a
/// Host endpoint has passed build verification. All domain facades preserve the
/// official request path and typed payload/value boundary while hiding HTTP URLs,
/// wire envelopes and raw JSON values from feature code.
struct HarnessAPIs: Sendable {
    let settings: SettingsAPI
    let credentials: CredentialsAPI
    let llm: LLMAPI
    let skills: SkillsAPI
    let agentPresets: AgentPresetsAPI
    let downloads: DownloadsAPI
    let host: HostAPI

    init(
        baseURL: URL,
        accessPolicy: HostRPCAccessPolicy,
        diagnostics: HostDiagnosticRecorder,
        session: URLSession = .shared
    ) {
        let client = DSHAPIClient(
            baseURL: baseURL,
            accessPolicy: accessPolicy,
            diagnostics: diagnostics,
            session: session
        )
        settings = SettingsAPI(client: client)
        credentials = CredentialsAPI(client: client)
        llm = LLMAPI(client: client)
        skills = SkillsAPI(client: client)
        agentPresets = AgentPresetsAPI(client: client)
        downloads = DownloadsAPI(client: client)
        host = HostAPI(client: client)
    }
}

struct SessionsAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func list() async throws -> SessionListResponse { try await client.sessionList() }
    func search(query: String) async throws -> SessionSearchResponse { try await client.sessionSearch(query: query) }
    func create(workspaceID: String? = nil) async throws -> SessionCreateResponse { try await client.sessionCreate(workspaceID: workspaceID) }
    func history(sessionID: String, beforeSeq: Int? = nil, maxMessages: Int? = nil) async throws -> SessionHistoryResponse {
        try await client.sessionHistory(sessionID: sessionID, beforeSeq: beforeSeq, maxMessages: maxMessages)
    }
    func prompt(sessionID: String, content: [SessionPromptContent], mode: SessionPromptMode) async throws -> SessionPromptResponse {
        try await client.sessionPrompt(sessionID: sessionID, content: content, mode: mode)
    }
    func cancel(sessionID: String) async throws -> SessionCancelResponse { try await client.sessionCancel(sessionID: sessionID) }
    /// Source: RC8 `sessions.schema.ts:sessionUpdateQueueRequestSchema`.
    func updateQueue(_ request: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
        try await client.call("session.updateQueue", payload: request)
    }
    func models(sessionID: String) async throws -> SessionModelsResponse { try await client.sessionModels(sessionID: sessionID) }
    /// Source: RC8 `SessionAPI.selectModel`; visible selection is Host-confirmed.
    func selectModel(_ request: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
        try await client.sessionSelectModel(request)
    }
    func rename(sessionID: String, title: String) async throws -> SessionRenameResponse { try await client.sessionRename(sessionID: sessionID, title: title) }
    func fork(sessionID: String, atSeq: Int? = nil) async throws -> SessionForkResponse { try await client.sessionFork(sessionID: sessionID, atSeq: atSeq) }

    /// Source: approvals/question response payloads carried by `ClientResponse`.
    func answerApproval(rpcID: String, sessionID: String, approvalID: String, outcome: ApprovalOutcome) async throws -> RPCReceipt {
        try await client.respond(rpcID: rpcID, value: ApprovalResponsePayload(sessionId: sessionID, approvalId: approvalID, outcome: outcome.rawValue))
    }

    func answerQuestion(rpcID: String, sessionID: String, answers: [QuestionAnswerResponse]) async throws -> RPCReceipt {
        try await client.respond(rpcID: rpcID, value: QuestionResponsePayload(sessionId: sessionID, answer: QuestionAnswerBatch(answers: answers)))
    }

    func cancelQuestion(rpcID: String) async throws -> RPCReceipt {
        try await client.respondFailure(
            rpcID: rpcID,
            error: RPCBusinessError(code: "cancelled", message: "the user closed this question request", details: .object([:]))
        )
    }
}

/// Typed RC8 subagent domain. A catalog is Host authority and is never
/// reconstructed from ordinary session summaries.
struct SubagentsAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func list(parentSessionID: String) async throws -> SubagentListResponse {
        try await client.subagentList(parentSessionID: parentSessionID)
    }

    func prompt(_ request: SubagentPromptRequest) async throws -> SubagentPromptResponse {
        try await client.subagentPrompt(request)
    }

    func interrupt(_ request: SubagentInterruptRequest) async throws -> SubagentInterruptResponse {
        try await client.subagentInterrupt(request)
    }
}

/// Typed RC8 `messageFeedback` Remote namespace. Business failures remain
/// result payloads rather than being collapsed into transport failures.
struct MessageFeedbackAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func list(sessionID: String) async throws -> MessageFeedbackListResponse {
        try await client.call("messageFeedback.list", payload: MessageFeedbackListRequest(sessionId: sessionID))
    }

    func put(_ request: MessageFeedbackPutRequest) async throws -> MessageFeedbackPutResponse {
        try await client.call("messageFeedback.put", payload: request)
    }

    func delete(_ request: MessageFeedbackDeleteRequest) async throws -> MessageFeedbackDeleteResponse {
        try await client.call("messageFeedback.delete", payload: request)
    }
}

/// Source: `packages/feedback/message-feedback/src/types.ts` at RC8.
enum MessageFeedbackRatingDTO: String, Codable, Sendable, Equatable {
    case positive
    case negative
}

struct MessageFeedbackItemDTO: Codable, Sendable, Equatable, Identifiable {
    let messageId: String
    let rating: MessageFeedbackRatingDTO
    let note: String?
    /// Equality-only Host mutation token; never interpreted or locally incremented.
    let version: String
    let createdAt: Int
    let updatedAt: Int

    var id: String { messageId }
}

struct MessageFeedbackListRequest: Codable, Sendable, Equatable {
    let sessionId: String
}

struct MessageFeedbackPutRequest: Codable, Sendable, Equatable {
    let sessionId: String
    let messageId: String
    let rating: MessageFeedbackRatingDTO
    let note: String?
    /// RC8 distinguishes an explicit null (require absent) from an omitted wire field.
    let ifVersion: String?

    private enum CodingKeys: String, CodingKey { case sessionId, messageId, rating, note, ifVersion }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(messageId, forKey: .messageId)
        try container.encode(rating, forKey: .rating)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(ifVersion, forKey: .ifVersion)
    }
}

struct MessageFeedbackDeleteRequest: Codable, Sendable, Equatable {
    let sessionId: String
    let messageId: String
    let ifVersion: String
}

/// Stable RC8 business error carrier. Optional fields cover the precise
/// version-conflict `current` projection without inventing client recovery.
struct MessageFeedbackBusinessErrorDTO: Codable, Sendable, Equatable {
    let code: String
    let sessionId: String?
    let messageId: String?
    let current: MessageFeedbackItemDTO?
    let maxBytes: Int?
    let actualBytes: Int?
}

struct MessageFeedbackListValueDTO: Codable, Sendable, Equatable {
    let items: [MessageFeedbackItemDTO]
}

struct MessageFeedbackDeleteValueDTO: Codable, Sendable, Equatable {
    let absent: Bool
}

struct MessageFeedbackListResponse: Codable, Sendable, Equatable {
    let ok: Bool
    let value: MessageFeedbackListValueDTO?
    let error: MessageFeedbackBusinessErrorDTO?
}

struct MessageFeedbackPutResponse: Codable, Sendable, Equatable {
    let ok: Bool
    let value: MessageFeedbackItemDTO?
    let error: MessageFeedbackBusinessErrorDTO?
}

struct MessageFeedbackDeleteResponse: Codable, Sendable, Equatable {
    let ok: Bool
    let value: MessageFeedbackDeleteValueDTO?
    let error: MessageFeedbackBusinessErrorDTO?
}

struct WorkspacesAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func list() async throws -> WorkspaceListResponse { try await client.workspaceList() }
    func create(path: String) async throws -> WorkspaceCreateResponse { try await client.workspaceCreate(path: path) }
    func rename(workspaceID: String, title: String) async throws -> WorkspaceRenameResponse { try await client.workspaceRename(workspaceID: workspaceID, title: title) }
    func delete(workspaceID: String) async throws -> WorkspaceDeleteResponse { try await client.workspaceDelete(workspaceID: workspaceID) }
    func insertBefore(workspaceID: String, beforeWorkspaceID: String? = nil) async throws -> WorkspaceInsertBeforeResponse {
        try await client.workspaceInsertBefore(workspaceID: workspaceID, beforeWorkspaceID: beforeWorkspaceID)
    }
    func insertSessionBefore(workspaceID: String, sessionID: String, beforeSessionID: String? = nil) async throws -> WorkspaceInsertSessionBeforeResponse {
        try await client.workspaceInsertSessionBefore(workspaceID: workspaceID, sessionID: sessionID, beforeSessionID: beforeSessionID)
    }
    func archiveSession(sessionID: String) async throws -> WorkspaceArchiveSessionResponse { try await client.workspaceArchiveSession(sessionID: sessionID) }
}

struct SettingsAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func describe() async throws -> SettingsDescribeResponse { try await client.settingsDescribe() }
    func mutate(namespace: String, operations: [SettingsPathOperationDTO], expectedRevision: Int?) async throws -> SettingsNamespaceDTO {
        try await client.settingsMutate(namespace: namespace, operations: operations, expectedRevision: expectedRevision)
    }
}

protocol NativeCredentialAPI: Sendable {
    func describe(refs: [String]) async throws -> CredentialsDescribeResponse
    func set(ref: String, value: String) async throws -> EmptyRPCResponse
    func unset(ref: String) async throws -> EmptyRPCResponse
}

struct CredentialsAPI: Sendable, NativeCredentialAPI {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func describe(refs: [String]) async throws -> CredentialsDescribeResponse {
        try await client.call("credentials.describe", payload: CredentialsDescribeRequest(refs: refs))
    }
    func set(ref: String, value: String) async throws -> EmptyRPCResponse {
        try await client.call("credentials.set", payload: CredentialsSetRequest(ref: ref, value: value))
    }
    func unset(ref: String) async throws -> EmptyRPCResponse {
        try await client.call("credentials.unset", payload: CredentialsUnsetRequest(ref: ref))
    }
}

protocol NativeLLMDirectoryAPI: Sendable {
    func providers() async throws -> LLMProvidersResponse
    func models() async throws -> LLMModelsResponse
    func discoverModels(_ request: LLMDiscoverModelsRequest) async throws -> LLMDiscoverModelsResponse
}

struct LLMAPI: Sendable, NativeLLMDirectoryAPI {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func providers() async throws -> LLMProvidersResponse {
        try await client.call("llm.providers", payload: EmptyPayload())
    }
    func models() async throws -> LLMModelsResponse {
        try await client.call("llm.models", payload: EmptyPayload())
    }
    func discoverModels(_ request: LLMDiscoverModelsRequest) async throws -> LLMDiscoverModelsResponse {
        try await client.call("llm.discoverModels", payload: request)
    }
}

/// The locked RPC map names this mutation-only domain `goals`; the native facade
/// uses CommandsAPI to keep Features independent of the wire path vocabulary.
struct CommandsAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func create(_ request: GoalCreateRequest) async throws -> GoalReferenceResponse { try await client.call("goal.create", payload: request) }
    func edit(_ request: GoalEditRequest) async throws -> GoalReferenceResponse { try await client.call("goal.edit", payload: request) }
    func pause(_ request: GoalReferenceRequest) async throws -> GoalReferenceResponse { try await client.call("goal.pause", payload: request) }
    func resume(_ request: GoalReferenceRequest) async throws -> GoalReferenceResponse { try await client.call("goal.resume", payload: request) }
    func complete(_ request: GoalReferenceRequest) async throws -> GoalReferenceResponse { try await client.call("goal.complete", payload: request) }
    func clear(_ request: GoalReferenceRequest) async throws -> GoalClearResponse { try await client.call("goal.clear", payload: request) }
}

struct SkillsAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func list(sessionID: String) async throws -> SkillsListResponse {
        try await client.call("skill.list", payload: SkillsListRequest(sessionId: sessionID))
    }
}

protocol NativeAgentPresetAPI: Sendable {
    func list() async throws -> AgentPresetListResponse
    func select(sessionID: String, agentPreset: String) async throws -> AgentPresetSelectResponse
    func read(agentPreset: String) async throws -> AgentPresetReadResponse
    func copy(_ request: AgentPresetCopyRequest) async throws -> AgentPresetCopyResponse
    func openDocument(agentPreset: String) async throws -> AgentPresetOpenDocumentResponse
    func remove(agentPreset: String) async throws -> EmptyRPCResponse
}

struct AgentPresetsAPI: Sendable, NativeAgentPresetAPI {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func list() async throws -> AgentPresetListResponse { try await client.call("agentPreset.list", payload: EmptyPayload()) }
    func select(sessionID: String, agentPreset: String) async throws -> AgentPresetSelectResponse {
        try await client.call("agentPreset.select", payload: AgentPresetSelectRequest(sessionId: sessionID, agentPreset: agentPreset))
    }
    func read(agentPreset: String) async throws -> AgentPresetReadResponse {
        try await client.call("agentPreset.read", payload: AgentPresetReadRequest(agentPreset: agentPreset))
    }
    func copy(_ request: AgentPresetCopyRequest) async throws -> AgentPresetCopyResponse {
        try await client.call("agentPreset.copy", payload: request)
    }
    func openDocument(agentPreset: String) async throws -> AgentPresetOpenDocumentResponse {
        try await client.call("agentPreset.openDocument", payload: AgentPresetOpenDocumentRequest(agentPreset: agentPreset))
    }
    func remove(agentPreset: String) async throws -> EmptyRPCResponse {
        try await client.call("agentPreset.remove", payload: AgentPresetRemoveRequest(agentPreset: agentPreset))
    }
}

struct DownloadsAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func sessionLogURL(sessionID: String, includeDescendants: Bool = true) async throws -> URL {
        try await client.transport.downloadURL(sessionID: sessionID, includeDescendants: includeDescendants)
    }

    func exportSessionLog(
        sessionID: String,
        includeDescendants: Bool = true,
        exporter: SessionLogExporter
    ) async throws -> SessionLogExport {
        try await exporter.export(sessionID: sessionID, includeDescendants: includeDescendants, downloads: self)
    }
}

struct HostAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func describe() async throws -> HostDescribeResponse { try await client.hostDescribe() }

    /// The Host owns the actual filesystem/desktop action. Consumers receive
    /// only this typed intent and never a local file URL opener.
    func openPath(_ path: String) async throws -> HostOpenPathResponse {
        try await client.hostOpenPath(path: path)
    }
}

// MARK: - ServerRequest response DTOs

enum ApprovalOutcome: String, Codable, Sendable { case allowedOnce = "allowed-once"; case rejected }
struct ApprovalResponsePayload: Codable, Sendable { let sessionId: String; let approvalId: String; let outcome: String }
struct QuestionAnswerResponse: Codable, Sendable { let id: String; let selected: [String]; let custom: String? }
private struct QuestionAnswerBatch: Codable, Sendable { let answers: [QuestionAnswerResponse] }
private struct QuestionResponsePayload: Codable, Sendable { let sessionId: String; let answer: QuestionAnswerBatch }

// MARK: - Credentials DTOs

struct EmptyRPCResponse: Codable, Sendable {}
struct CredentialsDescribeRequest: Codable, Sendable { let refs: [String] }
struct CredentialsSetRequest: Codable, Sendable { let ref: String; let value: String }
struct CredentialsUnsetRequest: Codable, Sendable { let ref: String }
struct CredentialsDescribeResponse: Codable, Sendable { let credentials: [String: CredentialViewDTO] }
struct CredentialViewDTO: Codable, Sendable { let configured: Bool; let source: String?; let writable: Bool }

// MARK: - LLM DTOs

struct LLMProviderDTO: Codable, Sendable, Identifiable {
    let provider: String
    let displayName: String
    let settingsNs: String
    let settingsPath: [String]
    let active: Bool
    let declared: Bool?
    var id: String { provider }
}
struct LLMProvidersResponse: Codable, Sendable { let providers: [LLMProviderDTO] }
struct LLMModelDTO: Codable, Sendable, Identifiable { let id: String; let name: String; let description: String? }
struct LLMModelGroupDTO: Codable, Sendable, Identifiable { let id: String; let name: String; let models: [LLMModelDTO] }
struct LLMModelFailureDTO: Codable, Sendable, Identifiable { let id: String; let name: String; let message: String }
struct LLMModelsResponse: Codable, Sendable { let groups: [LLMModelGroupDTO]; let failures: [LLMModelFailureDTO] }
struct LLMDiscoverModelsRequest: Codable, Sendable {
    let settingsNs: String
    let provider: String?
    let baseURL: String?
    let api: String?
    let apiKey: String?
}
struct LLMDiscoveredModelDTO: Codable, Sendable, Identifiable { let id: String; let name: String?; let contextWindow: Int?; let maxTokens: Int? }
struct LLMDiscoverModelsResponse: Codable, Sendable { let models: [LLMDiscoveredModelDTO] }

// MARK: - Subagent DTOs

/// Source: RC8 `subagents.ts:13-63`. `kind` controls which optional fields are
/// meaningful; callers must fail closed for malformed combinations.
struct SubagentListRequest: Codable, Sendable, Equatable { let parentSessionId: String }
struct SubagentListEntryDTO: Codable, Sendable, Equatable {
    let kind: String
    let id: String
    let activity: String?
    let hasChildren: Bool?
    let mode: String?
    let label: String?
    let reason: String?
}
struct SubagentListResponse: Codable, Sendable, Equatable {
    let entries: [SubagentListEntryDTO]
    let parentAvailable: Bool
}
/// RC8 `SubagentAddress` narrowed to the only mode permitted for prompt and
/// interrupt. The caller supplies no free-form mode string.
struct SubagentPromptRequest: Codable, Sendable, Equatable {
    let parentSessionId: String
    let childSessionId: String
    let mode: String = "continuable"
    let content: [SessionPromptContent]
    let clientTimeZone: String?
}
struct SubagentPromptResponse: Codable, Sendable, Equatable { let messageId: String }
struct SubagentInterruptRequest: Codable, Sendable, Equatable {
    let parentSessionId: String
    let childSessionId: String
    let mode: String = "continuable"
}
struct SubagentInterruptResponse: Codable, Sendable, Equatable { let accepted: Bool }

// MARK: - Goals / command DTOs

struct GoalReferenceDTO: Codable, Sendable, Equatable { let id: String; let revision: Int }
struct GoalReferenceResponse: Codable, Sendable { let ref: GoalReferenceDTO }
struct GoalCreateRequest: Codable, Sendable { let sessionId: String; let objective: String; let maxGoalRounds: Int? }
struct GoalEditRequest: Codable, Sendable { let sessionId: String; let ref: GoalReferenceDTO; let objective: String?; let maxGoalRounds: Int? }
struct GoalReferenceRequest: Codable, Sendable, Equatable { let sessionId: String; let ref: GoalReferenceDTO }
struct GoalClearResponse: Codable, Sendable { let cleared: Bool }

// MARK: - Skills DTOs

struct SkillsListRequest: Codable, Sendable { let sessionId: String }
struct SkillEntryDTO: Codable, Sendable, Identifiable {
    let name: String
    let description: String
    let whenToUse: String?
    let modelInvocable: Bool
    var id: String { name }
}
struct SkillsListResponse: Codable, Sendable { let skills: [SkillEntryDTO] }

// MARK: - Agent preset DTOs

struct AgentPresetEntryDTO: Codable, Sendable, Identifiable {
    let id: String
    let trust: String
    let isDefault: Bool
    let name: String?
    let description: String?
    let broken: String?
}
struct AgentPresetListResponse: Codable, Sendable { let presets: [AgentPresetEntryDTO]; let authorable: Bool; let hasDocument: Bool }
struct AgentPresetSelectRequest: Codable, Sendable { let sessionId: String; let agentPreset: String }
struct AgentPresetSelectResponse: Codable, Sendable { let agentPreset: String }
struct AgentPresetReadRequest: Codable, Sendable { let agentPreset: String }
struct AgentPresetReadResponse: Codable, Sendable { let agentPreset: String; let trust: String; let content: String; let name: String?; let description: String? }
struct AgentPresetCopyRequest: Codable, Sendable { let from: String; let agentPreset: String; let name: String? }
struct AgentPresetCopyResponse: Codable, Sendable { let agentPreset: String }
struct AgentPresetOpenDocumentRequest: Codable, Sendable { let agentPreset: String }
struct AgentPresetOpenDocumentResponse: Codable, Sendable { let opened: Bool; let path: String? }
struct AgentPresetRemoveRequest: Codable, Sendable { let agentPreset: String }
