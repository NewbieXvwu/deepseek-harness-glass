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

    func workspaceList() async throws -> WorkspaceListResponse {
        try await call("workspace.list", payload: EmptyPayload())
    }

    func settingsDescribe() async throws -> SettingsDescribeResponse {
        try await call("settings.describe", payload: EmptyPayload())
    }
}

struct EmptyPayload: Codable, Sendable {}

/// These intentionally retain only stable top-level fields needed by the first
/// native readiness/browser phases. Per-domain DTOs expand only with official
/// schema fixtures; unknown fields remain decodable through Codable defaults.
struct HostDescribeResponse: Decodable, Sendable {
    let canOpenPath: Bool?
    let directoryPicker: String?
}

struct SessionListResponse: Decodable, Sendable {
    let sessions: [SessionSummaryDTO]?
}

struct SessionSummaryDTO: Decodable, Sendable, Identifiable {
    let id: String
    let title: String?
    let blank: Bool?
    let running: Bool?
}

struct WorkspaceListResponse: Decodable, Sendable {
    let workspaces: [WorkspaceSummaryDTO]?
    let archivedSessionIds: [String]?
}

struct WorkspaceSummaryDTO: Decodable, Sendable, Identifiable {
    let id: String
    let path: String?
    let name: String?
    let sessionIds: [String]?
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
