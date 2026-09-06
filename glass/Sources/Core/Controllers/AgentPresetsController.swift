import Foundation

struct AgentPresetsController: NativeAgentPresetAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func list() async throws -> AgentPresetListResponse {
        async let roster: Roster = remote.call(
            RemoteProcedure("agentPresets/list"),
            arguments: EmptyArguments()
        )
        async let canOpenDirectory: Bool = remote.call(
            RemoteProcedure("settings/canOpenAgentPresetDirectory"),
            arguments: EmptyArguments()
        )
        let (resolvedRoster, hasDocument) = try await (roster, canOpenDirectory)
        return AgentPresetListResponse(
            presets: resolvedRoster.presets,
            authorable: resolvedRoster.authorable,
            hasDocument: hasDocument
        )
    }

    func select(sessionID: String, agentPreset: String) async throws -> AgentPresetSelectResponse {
        let selected: String = try await remote.call(
            RemoteProcedure("agentPresets/select"),
            arguments: SelectArguments(agentId: sessionID, agentPreset: agentPreset)
        )
        return AgentPresetSelectResponse(agentPreset: selected)
    }

    func read(agentPreset: String) async throws -> AgentPresetReadResponse {
        try await remote.call(
            RemoteProcedure("agentPresets/read"),
            arguments: ReadArguments(agentPreset: agentPreset)
        )
    }

    func copy(_ request: AgentPresetCopyRequest) async throws -> AgentPresetCopyResponse {
        try await remote.callNoValue(
            endpoint: "agentPresets/copy",
            arguments: CopyArguments(from: request.from, id: request.agentPreset, name: request.name)
        )
        return AgentPresetCopyResponse(agentPreset: request.agentPreset)
    }

    func openDocument(agentPreset: String) async throws -> AgentPresetOpenDocumentResponse {
        try await remote.call(
            RemoteProcedure("settings/openAgentPresetDirectory"),
            arguments: ReadArguments(agentPreset: agentPreset)
        )
    }

    func remove(agentPreset: String) async throws -> EmptyRPCResponse {
        try await remote.callNoValue(
            endpoint: "agentPresets/deletePreset",
            arguments: DeleteArguments(id: agentPreset)
        )
        return EmptyRPCResponse()
    }

    private struct EmptyArguments: Codable, Sendable {}

    private struct Roster: Codable, Sendable {
        let presets: [AgentPresetEntryDTO]
        let authorable: Bool
    }

    private struct SelectArguments: Codable, Sendable {
        let agentId: String
        let agentPreset: String
    }

    private struct ReadArguments: Codable, Sendable {
        let agentPreset: String
    }

    private struct CopyArguments: Codable, Sendable {
        let from: String
        let id: String
        let name: String?
    }

    private struct DeleteArguments: Codable, Sendable {
        let id: String
    }
}
