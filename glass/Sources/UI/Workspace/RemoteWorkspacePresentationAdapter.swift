import Foundation

extension WorkspaceSummaryDTO {
    init(remote: RemoteWorkspaceView) {
        self.init(
            workspaceId: remote.workspaceId,
            path: remote.path,
            title: remote.title,
            sessionIds: remote.sessionIds,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt
        )
    }
}

extension SessionSummaryDTO {
    init(remote: RemoteSessionSummary) {
        let projections: SessionProjectionsDTO?
        if case let .object(block)? = remote.projections,
           case let .number(asOf)? = block["asOfSeq"],
           case let .object(values)? = block["values"] {
            projections = .init(
                asOfSeq: Int(asOf),
                values: values.mapValues(\.conversationJSONValue)
            )
        } else {
            projections = nil
        }
        self.init(
            sessionId: remote.sessionId,
            updatedAt: Double(remote.updatedAt),
            running: remote.running,
            blank: remote.blank,
            pendingInteraction: nil,
            parentSessionId: remote.parentSessionId,
            origin: remote.origin,
            cwd: remote.cwd,
            agentPreset: nil,
            projections: projections
        )
    }
}

extension SessionSearchItemDTO {
    init(remote: RemoteSessionSearchItem) {
        self.init(sessionId: remote.sessionId, snippet: remote.snippet)
    }
}
