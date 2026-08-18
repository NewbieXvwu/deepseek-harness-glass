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

        /// Source: `tree.ts:sessionVisible`. Blank sessions are provisional and
        /// only the selected one is shown; subagents stay out of this top-level
        /// browser even though their Host summaries remain in the snapshot.
        func isVisibleInBrowser(_ session: SessionSummaryDTO) -> Bool {
            session.origin != "subagent"
                && !archivedSessionIDs.contains(session.sessionId)
                && (!session.blank || session.sessionId == selectedSessionID)
        }

        var visibleSessions: [SessionSummaryDTO] {
            sessions.filter(isVisibleInBrowser)
        }

        func sessions(in workspace: WorkspaceSummaryDTO) -> [SessionSummaryDTO] {
            let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
            return workspace.sessionIds.compactMap { byID[$0] }
                .filter(isVisibleInBrowser)
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
    private var eventTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?

    /// Source: `events.schema.ts:hostFrameSchema`. A single list reload folds
    /// batches of related host increments into the host-authoritative snapshot.
    private static let browserAffectingHostMethods: Set<String> = [
        "host/session-added",
        "host/session-removed",
        "host/session-status",
        "host/workspace-changed",
        "host/workspace-removed",
        "host/workspace-order-changed",
        "host/archived-sessions-changed",
    ]

    deinit {
        refreshTask?.cancel()
        eventTask?.cancel()
        eventRefreshTask?.cancel()
    }

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

    /// Opens the official Host stream only after the controller has verified a
    /// supported endpoint. Server-request `method` is the official frame type.
    func observeHostEvents(at endpoint: URL, using api: DSHAPIClient) {
        eventTask?.cancel()
        let client = SSEClient(baseURL: endpoint)
        eventTask = Task { [weak self] in
            let stream = await client.stream(.host)
            do {
                for try await frame in stream {
                    guard Self.browserAffectingHostMethods.contains(frame.method) else { continue }
                    self?.scheduleRefresh(using: api)
                }
            } catch is CancellationError {
                return
            } catch {
                // Event reconnection policy belongs to Host lifecycle ownership.
                // A later successful host transition calls this method again.
            }
        }
    }

    func stopObservingHostEvents() {
        eventTask?.cancel()
        eventTask = nil
        eventRefreshTask?.cancel()
        eventRefreshTask = nil
    }

    private func scheduleRefresh(using api: DSHAPIClient) {
        eventRefreshTask?.cancel()
        eventRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refresh(using: api)
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
