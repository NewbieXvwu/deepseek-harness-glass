import Foundation

protocol WorkspaceControllerAPI: Sendable {
    func create(path: String) async throws -> RemoteWorkspaceCreateValue
    func rename(workspaceID: String, title: String) async throws -> RemoteWorkspaceValue
    func delete(workspaceID: String) async throws -> RemoteWorkspaceDeleteValue
    func insertBefore(workspaceID: String, beforeWorkspaceID: String?) async throws -> RemoteWorkspaceOrderValue
    func insertSessionBefore(workspaceID: String, sessionID: String, beforeSessionID: String?) async throws -> RemoteWorkspaceValue
    func archiveSession(sessionID: String) async throws -> RemoteWorkspaceArchiveValue
    func follow() async throws -> AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>
}

struct RemoteWorkspaceView: Codable, Sendable, Equatable, Identifiable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionIds: [String]
    let createdAt: String
    let updatedAt: String
    var id: String { workspaceId }
}

struct RemoteWorkspaceCreateValue: Codable, Sendable, Equatable {
    let workspace: RemoteWorkspaceView
    let created: Bool
}

struct RemoteWorkspaceValue: Codable, Sendable, Equatable { let workspace: RemoteWorkspaceView }
struct RemoteWorkspaceDeleteValue: Codable, Sendable, Equatable { let deleted: Bool }
struct RemoteWorkspaceOrderValue: Codable, Sendable, Equatable { let workspaceIds: [String] }
struct RemoteWorkspaceArchiveValue: Codable, Sendable, Equatable { let archivedSessionIds: [String] }


struct RemoteWorkspaceBaseline: Codable, Sendable, Equatable {
    let items: [RemoteWorkspaceView]
    let archivedSessionIds: [String]
}

enum RemoteWorkspaceFollowFrame: Codable, Sendable, Equatable {
    case baseline(RemoteWorkspaceBaseline)
    case upsert(RemoteWorkspaceView)
    case remove(String)
    case order([String])
    case archived([String])

    private enum CodingKeys: String, CodingKey { case type, value, workspace, workspaceId, workspaceIds, archivedSessionIds }
    private enum Kind: String, Codable { case baseline, upsert, remove, order, archived }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .baseline: self = .baseline(try container.decode(RemoteWorkspaceBaseline.self, forKey: .value))
        case .upsert: self = .upsert(try container.decode(RemoteWorkspaceView.self, forKey: .workspace))
        case .remove: self = .remove(try container.decode(String.self, forKey: .workspaceId))
        case .order: self = .order(try container.decode([String].self, forKey: .workspaceIds))
        case .archived: self = .archived(try container.decode([String].self, forKey: .archivedSessionIds))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .baseline(value): try container.encode(Kind.baseline, forKey: .type); try container.encode(value, forKey: .value)
        case let .upsert(workspace): try container.encode(Kind.upsert, forKey: .type); try container.encode(workspace, forKey: .workspace)
        case let .remove(id): try container.encode(Kind.remove, forKey: .type); try container.encode(id, forKey: .workspaceId)
        case let .order(ids): try container.encode(Kind.order, forKey: .type); try container.encode(ids, forKey: .workspaceIds)
        case let .archived(ids): try container.encode(Kind.archived, forKey: .type); try container.encode(ids, forKey: .archivedSessionIds)
        }
    }
}

struct WorkspaceController: WorkspaceControllerAPI, Sendable {
    private let remote: RemoteConnection
    init(remote: RemoteConnection) { self.remote = remote }

    func create(path: String) async throws -> RemoteWorkspaceCreateValue {
        try await remote.call(RemoteProcedure(.workspaceCreate), arguments: CreateArguments(request: .init(path: path)))
    }

    func rename(workspaceID: String, title: String) async throws -> RemoteWorkspaceValue {
        try await remote.call(RemoteProcedure(.workspaceRename), arguments: RenameArguments(request: .init(workspaceId: workspaceID, title: title)))
    }

    func delete(workspaceID: String) async throws -> RemoteWorkspaceDeleteValue {
        try await remote.call(RemoteProcedure(.workspaceDelete), arguments: DeleteArguments(request: .init(workspaceId: workspaceID)))
    }

    func insertBefore(workspaceID: String, beforeWorkspaceID: String?) async throws -> RemoteWorkspaceOrderValue {
        try await remote.call(RemoteProcedure(.workspaceInsertBefore), arguments: InsertBeforeArguments(request: .init(workspaceId: workspaceID, beforeWorkspaceId: beforeWorkspaceID)))
    }

    func insertSessionBefore(workspaceID: String, sessionID: String, beforeSessionID: String?) async throws -> RemoteWorkspaceValue {
        try await remote.call(RemoteProcedure(.workspaceInsertSessionBefore), arguments: InsertSessionArguments(request: .init(workspaceId: workspaceID, sessionId: sessionID, beforeSessionId: beforeSessionID)))
    }

    func archiveSession(sessionID: String) async throws -> RemoteWorkspaceArchiveValue {
        try await remote.call(RemoteProcedure(.workspaceArchiveSession), arguments: ArchiveArguments(request: .init(sessionId: sessionID)))
    }

    func follow() async throws -> AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error> {
        try await remote.stream(RemoteStreamProcedure(.workspaceFollow), arguments: EmptyArguments())
    }

    private struct CreateRequest: Codable, Sendable { let path: String }
    private struct CreateArguments: Codable, Sendable { let request: CreateRequest }
    private struct RenameRequest: Codable, Sendable { let workspaceId: String; let title: String }
    private struct RenameArguments: Codable, Sendable { let request: RenameRequest }
    private struct DeleteRequest: Codable, Sendable { let workspaceId: String }
    private struct DeleteArguments: Codable, Sendable { let request: DeleteRequest }
    private struct InsertBeforeRequest: Codable, Sendable { let workspaceId: String; let beforeWorkspaceId: String? }
    private struct InsertBeforeArguments: Codable, Sendable { let request: InsertBeforeRequest }
    private struct InsertSessionRequest: Codable, Sendable { let workspaceId: String; let sessionId: String; let beforeSessionId: String? }
    private struct InsertSessionArguments: Codable, Sendable { let request: InsertSessionRequest }
    private struct ArchiveRequest: Codable, Sendable { let sessionId: String }
    private struct ArchiveArguments: Codable, Sendable { let request: ArchiveRequest }
    private struct EmptyArguments: Codable, Sendable {}
}
