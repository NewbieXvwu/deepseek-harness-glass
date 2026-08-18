import Combine
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
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

    enum RemoteSearchStatus: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    struct RemoteSearch: Equatable {
        let query: String
        let status: RemoteSearchStatus
        let items: [SessionSearchItemDTO]
        let hasMore: Bool

        static let idle = RemoteSearch(query: "", status: .idle, items: [], hasMore: false)
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
    @Published private(set) var remoteSearch: RemoteSearch = .idle

    private var refreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
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
        searchTask?.cancel()
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
    func observeHostEvents(at endpoint: URL, using api: DSHAPIClient, diagnostics: HostDiagnosticRecorder) {
        eventTask?.cancel()
        let client = SSEClient(baseURL: endpoint)
        eventTask = Task { [weak self] in
            let stream = await client.stream(.host)
            do {
                for try await frame in stream {
                    await diagnostics.recordSSEActivity()
                    guard Self.browserAffectingHostMethods.contains(frame.method) else { continue }
                    self?.scheduleRefresh(using: api)
                }
            } catch is CancellationError {
                return
            } catch {
                await diagnostics.recordRPCError(error)
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

    /// Called by lifecycle ownership whenever the verified Host endpoint is no
    /// longer ready. No durable browser data is retained outside the Host.
    func detachHost() {
        refreshTask?.cancel()
        refreshTask = nil
        stopObservingHostEvents()
        phase = .idle
        snapshot = .empty
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
        remoteSearch = .idle
    }

    /// Source: `WorkspaceBrowser.tsx:SEARCH_DEBOUNCE_MS` and
    /// `session-search.ts:SESSION_SEARCH_RESULT_LIMIT`. The store owns request
    /// cancellation and stale result suppression; the view only binds text.
    func search(query: String, using api: DSHAPIClient?) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !normalized.isEmpty else {
            remoteSearch = .idle
            return
        }
        remoteSearch = RemoteSearch(query: normalized, status: .loading, items: [], hasMore: false)
        guard let api else {
            remoteSearch = RemoteSearch(query: normalized, status: .failed, items: [], hasMore: false)
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let response = try await api.sessionSearch(query: normalized)
                guard !Task.isCancelled, self?.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == normalized else { return }
                self?.remoteSearch = RemoteSearch(
                    query: normalized,
                    status: .ready,
                    items: response.items,
                    hasMore: response.hasMore
                )
            } catch {
                guard !Task.isCancelled, self?.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == normalized else { return }
                self?.remoteSearch = RemoteSearch(query: normalized, status: .failed, items: [], hasMore: false)
            }
        }
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

    /// Snapshot-only projection of the locked official resident fixture. It uses
    /// the same list-RPC DTOs as production and never participates in Host I/O.
    func loadSnapshotFixtureWorkspace() {
        let workspaceID = "fx-ws-fixture"
        let alphaID = "fx-alpha"
        let betaID = "fx-beta"
        let gammaID = "fx-gamma"
        let projection = { (title: String) in
            SessionProjectionsDTO(asOfSeq: 0, values: ["title": .string(title)])
        }
        let now = Date().timeIntervalSince1970 * 1_000
        let sessions = [
            SessionSummaryDTO(
                sessionId: alphaID,
                updatedAt: now,
                running: true,
                blank: false,
                pendingInteraction: "question",
                parentSessionId: nil,
                origin: nil,
                cwd: "/tmp/fixture",
                agentPreset: nil,
                projections: projection("Fixture 历史会话")
            ),
            SessionSummaryDTO(
                sessionId: betaID,
                updatedAt: now - 60 * 1_000,
                running: false,
                blank: false,
                pendingInteraction: nil,
                parentSessionId: alphaID,
                origin: nil,
                cwd: "/tmp/fixture",
                agentPreset: nil,
                projections: projection("fixture")
            ),
            SessionSummaryDTO(
                sessionId: gammaID,
                updatedAt: now - 2 * 60 * 1_000,
                running: false,
                blank: false,
                pendingInteraction: nil,
                parentSessionId: nil,
                origin: nil,
                cwd: "/tmp/fixture",
                agentPreset: nil,
                projections: projection("fixture")
            ),
        ]
        snapshot = Snapshot(
            workspaces: [
                WorkspaceSummaryDTO(
                    workspaceId: workspaceID,
                    path: "/tmp/fixture",
                    title: "fixture",
                    sessionIds: [alphaID, betaID, gammaID],
                    createdAt: "1970-01-01T00:00:00.000Z",
                    updatedAt: "1970-01-01T00:00:00.000Z"
                ),
            ],
            sessions: sessions,
            archivedSessionIDs: [],
            selectedSessionID: alphaID,
            selectedWorkspaceID: workspaceID
        )
        phase = .ready
    }

    /// Snapshot-only projection used by the workspace management dialogs. The
    /// official baseline keeps `fixture` selected while the welcome composer,
    /// rather than a historical session transcript, remains visible.
    func loadSnapshotFixtureWorkspaceWelcome() {
        loadSnapshotFixtureWorkspace()
        snapshot = Snapshot(
            workspaces: snapshot.workspaces,
            sessions: snapshot.sessions,
            archivedSessionIDs: snapshot.archivedSessionIDs,
            selectedSessionID: nil,
            selectedWorkspaceID: snapshot.selectedWorkspaceID
        )
        searchQuery = ""
        remoteSearch = .idle
    }

    /// Snapshot-only projection for the official workspace browser's local +
    /// `session.search` merged-results state. The query and snippets are
    /// deterministic, while all session identity remains the shared fixture.
    func loadSnapshotFixtureSearch() {
        loadSnapshotFixtureWorkspace()
        snapshot = Snapshot(
            workspaces: snapshot.workspaces,
            sessions: snapshot.sessions,
            archivedSessionIDs: snapshot.archivedSessionIDs,
            selectedSessionID: nil,
            selectedWorkspaceID: snapshot.selectedWorkspaceID
        )
        searchQuery = "fixture"
        remoteSearch = RemoteSearch(
            query: "fixture",
            status: .ready,
            items: [
                SessionSearchItemDTO(
                    sessionId: "fx-alpha",
                    snippet: OfficialUISpec.Text.fixtureSearchSnippet
                ),
            ],
            hasMore: false
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
