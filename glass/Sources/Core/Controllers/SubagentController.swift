import Foundation

protocol SubagentControllerAPI: Sendable {
    func list(parentSessionID: String) async throws -> RemoteSubagentCatalog
    func prompt(_ request: RemoteSubagentPromptRequest) async throws -> RemoteSubagentPromptReceipt
    func interrupt(parentSessionID: String, childSessionID: String) async throws -> RemoteSubagentInterruptReceipt
}

enum RemoteSubagentListEntry: Codable, Sendable, Equatable, Identifiable {
    case child(RemoteSubagentChild)
    case diagnostic(RemoteSubagentDiagnostic)

    var id: String {
        switch self {
        case let .child(child): child.id
        case let .diagnostic(diagnostic): diagnostic.id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id, activity, hasChildren, mode, label, reason
    }

    private enum Kind: String, Codable { case child, diagnostic }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .child:
            let mode = try container.decode(RemoteSubagentMode.self, forKey: .mode)
            let label = try container.decodeIfPresent(String.self, forKey: .label)
            if mode == .continuable, label == nil {
                throw DecodingError.dataCorruptedError(
                    forKey: .label,
                    in: container,
                    debugDescription: "continuable subagent child requires label"
                )
            }
            self = .child(.init(
                id: try container.decode(String.self, forKey: .id),
                activity: try container.decode(RemoteSubagentActivity.self, forKey: .activity),
                hasChildren: try container.decode(Bool.self, forKey: .hasChildren),
                mode: mode,
                label: label
            ))
        case .diagnostic:
            self = .diagnostic(.init(
                id: try container.decode(String.self, forKey: .id),
                reason: try container.decode(RemoteSubagentDiagnosticReason.self, forKey: .reason)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .child(child):
            try container.encode(Kind.child, forKey: .kind)
            try container.encode(child.id, forKey: .id)
            try container.encode(child.activity, forKey: .activity)
            try container.encode(child.hasChildren, forKey: .hasChildren)
            try container.encode(child.mode, forKey: .mode)
            try container.encodeIfPresent(child.label, forKey: .label)
        case let .diagnostic(diagnostic):
            try container.encode(Kind.diagnostic, forKey: .kind)
            try container.encode(diagnostic.id, forKey: .id)
            try container.encode(diagnostic.reason, forKey: .reason)
        }
    }
}

enum RemoteSubagentMode: String, Codable, Sendable { case oneShot = "one-shot", continuable }
enum RemoteSubagentActivity: String, Codable, Sendable { case running, inactive }
enum RemoteSubagentDiagnosticReason: String, Codable, Sendable { case corrupt, unsupported, unavailable }

struct RemoteSubagentChild: Sendable, Equatable, Identifiable {
    let id: String
    let activity: RemoteSubagentActivity
    let hasChildren: Bool
    let mode: RemoteSubagentMode
    let label: String?
}

struct RemoteSubagentDiagnostic: Sendable, Equatable, Identifiable {
    let id: String
    let reason: RemoteSubagentDiagnosticReason
}

struct RemoteSubagentCatalog: Codable, Sendable, Equatable {
    let entries: [RemoteSubagentListEntry]
    let parentAvailable: Bool
}

struct RemoteSubagentPromptRequest: Codable, Sendable, Equatable {
    let requestId: SessionRequestID
    let parentSessionId: String
    let childSessionId: String
    let mode: RemoteSubagentMode
    let content: [RemotePromptContentPart]
    let clientTimeZone: String?

    init(
        requestId: SessionRequestID,
        parentSessionId: String,
        childSessionId: String,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) {
        self.requestId = requestId
        self.parentSessionId = parentSessionId
        self.childSessionId = childSessionId
        self.mode = .continuable
        self.content = content
        self.clientTimeZone = clientTimeZone
    }
}

struct RemoteSubagentPromptReceipt: Codable, Sendable, Equatable {
    let messageId: String
}

struct RemoteSubagentInterruptReceipt: Codable, Sendable, Equatable {
    let accepted: Bool
}

struct SubagentController: SubagentControllerAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func list(parentSessionID: String) async throws -> RemoteSubagentCatalog {
        try await remote.call(
            RemoteProcedure(.subagentsList),
            arguments: ListArguments(parentSessionId: parentSessionID)
        )
    }

    func prompt(_ request: RemoteSubagentPromptRequest) async throws -> RemoteSubagentPromptReceipt {
        try await remote.call(
            RemoteProcedure(.subagentsPrompt),
            arguments: PromptArguments(request: request)
        )
    }

    func interrupt(parentSessionID: String, childSessionID: String) async throws -> RemoteSubagentInterruptReceipt {
        try await remote.call(
            RemoteProcedure(.subagentsInterruptByParent),
            arguments: InterruptArguments(
                childSessionId: childSessionID,
                parentSessionId: parentSessionID,
                mode: RemoteSubagentMode.continuable
            )
        )
    }

    private struct ListArguments: Codable, Sendable {
        let parentSessionId: String
    }

    private struct PromptArguments: Codable, Sendable {
        let request: RemoteSubagentPromptRequest
    }

    private struct InterruptArguments: Codable, Sendable {
        let childSessionId: String
        let parentSessionId: String
        let mode: RemoteSubagentMode
    }
}
