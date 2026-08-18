import Combine
import Foundation

/// Host-authoritative sidebar browser state. Ordering preferences and transient
/// expansion will be added only after their official persistence contract is
/// mapped; this store never invents a second durable workspace database.
@MainActor
final class NativeWorkspaceStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    struct Snapshot {
        let workspaces: [WorkspaceSummaryDTO]
        let sessions: [SessionSummaryDTO]
        let archivedSessionIDs: Set<String>
        let selectedSessionID: String?
        let selectedWorkspaceID: String?

        static let empty = Snapshot(
            workspaces: [],
            sessions: [],
            archivedSessionIDs: [],
            selectedSessionID: nil,
            selectedWorkspaceID: nil
        )

        var visibleSessions: [SessionSummaryDTO] {
            sessions.filter { !archivedSessionIDs.contains($0.sessionId) && !$0.blank }
        }

        func sessions(in workspace: WorkspaceSummaryDTO) -> [SessionSummaryDTO] {
            let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
            return workspace.sessionIds.compactMap { byID[$0] }
                .filter { !archivedSessionIDs.contains($0.sessionId) }
        }

        var ungroupedSessions: [SessionSummaryDTO] {
            let accounted = Set(workspaces.flatMap(\.sessionIds))
            return visibleSessions.filter { !accounted.contains($0.sessionId) }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var snapshot: Snapshot = .empty
    @Published var searchQuery = ""

    private var refreshTask: Task<Void, Never>?

    deinit { refreshTask?.cancel() }

    func refresh(using api: DSHAPIClient) {
        refreshTask?.cancel()
        phase = .loading
        refreshTask = Task { [weak self] in
            do {
                async let workspaceResponse = api.workspaceList()
                async let sessionResponse = api.sessionList()
                let (workspaces, sessions) = try await (workspaceResponse, sessionResponse)
                guard !Task.isCancelled else { return }
                let old = self?.snapshot ?? .empty
                self?.snapshot = Snapshot(
                    workspaces: workspaces.items,
                    sessions: sessions.items,
                    archivedSessionIDs: Set(workspaces.archivedSessionIds),
                    selectedSessionID: old.selectedSessionID,
                    selectedWorkspaceID: old.selectedWorkspaceID
                )
                self?.phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func select(sessionID: String?, workspaceID: String?) {
        snapshot = Snapshot(
            workspaces: snapshot.workspaces,
            sessions: snapshot.sessions,
            archivedSessionIDs: snapshot.archivedSessionIDs,
            selectedSessionID: sessionID,
            selectedWorkspaceID: workspaceID
        )
    }

    func applyHostWorkspaceList(_ workspaces: WorkspaceListResponse, sessions: SessionListResponse) {
        let old = snapshot
        snapshot = Snapshot(
            workspaces: workspaces.items,
            sessions: sessions.items,
            archivedSessionIDs: Set(workspaces.archivedSessionIds),
            selectedSessionID: old.selectedSessionID,
            selectedWorkspaceID: old.selectedWorkspaceID
        )
        phase = .ready
    }
}
