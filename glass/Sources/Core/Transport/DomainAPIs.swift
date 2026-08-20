import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// The sole Core composition root exposed to native Feature/UI modules after a
/// Host endpoint has passed build verification. All domain facades preserve the
/// official request path and typed payload/value boundary while hiding HTTP URLs,
/// wire envelopes and raw JSON values from feature code.
struct HarnessAPIs: Sendable {
    let sessions: SessionsAPI
    let workspaces: WorkspacesAPI
    let settings: SettingsAPI
    let credentials: CredentialsAPI
    let llm: LLMAPI
    let commands: CommandsAPI
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
        sessions = SessionsAPI(client: client)
        workspaces = WorkspacesAPI(client: client)
        settings = SettingsAPI(client: client)
        credentials = CredentialsAPI(client: client)
        llm = LLMAPI(client: client)
        commands = CommandsAPI(client: client)
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
    func models(sessionID: String) async throws -> SessionModelsResponse { try await client.sessionModels(sessionID: sessionID) }
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

struct WorkspacesAPI: Sendable {
    private let client: DSHAPIClient
    init(client: DSHAPIClient) { self.client = client }

    func list() async throws -> WorkspaceListResponse { try await client.workspaceList() }
    func create(path: String) async throws -> WorkspaceCreateResponse { try await client.workspaceCreate(path: path) }
    func rename(workspaceID: String, title: String) async throws -> WorkspaceRenameResponse { try await client.workspaceRename(workspaceID: workspaceID, title: title) }
    func delete(workspaceID: String) async throws -> WorkspaceDeleteResponse { try await client.workspaceDelete(workspaceID: workspaceID) }
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

struct CredentialsAPI: Sendable {
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

struct LLMAPI: Sendable {
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

struct AgentPresetsAPI: Sendable {
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

// MARK: - Goals / command DTOs

struct GoalReferenceDTO: Codable, Sendable { let id: String; let revision: Int }
struct GoalReferenceResponse: Codable, Sendable { let ref: GoalReferenceDTO }
struct GoalCreateRequest: Codable, Sendable { let sessionId: String; let objective: String; let maxGoalRounds: Int? }
struct GoalEditRequest: Codable, Sendable { let sessionId: String; let ref: GoalReferenceDTO; let objective: String?; let maxGoalRounds: Int? }
struct GoalReferenceRequest: Codable, Sendable { let sessionId: String; let ref: GoalReferenceDTO }
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
