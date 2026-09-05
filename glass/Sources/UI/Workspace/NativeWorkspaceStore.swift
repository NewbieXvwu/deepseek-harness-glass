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

    /// RC8 Host workspace summaries use JavaScript ISO strings, whose usual
    /// representation includes milliseconds. `ISO8601DateFormatter` does not
    /// parse that form unless fractional seconds are opted in explicitly.
    private static let workspaceCreationFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var snapshot: Snapshot = .empty
    @Published var searchQuery = ""
    @Published private(set) var remoteSearch: RemoteSearch = .idle

    /// Allows an already-authoritative complete Host snapshot to seed a native
    /// presentation. Production keeps the default empty state and transitions
    /// only through `refresh(using:)`; tests and shell restore paths can inject
    /// a complete value without constructing a second client-side database.
    init(initialSnapshot: Snapshot = .empty) {
        snapshot = initialSnapshot
    }

    private var refreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private var remoteWorkspaceTask: Task<Void, Never>?
    private var remoteCatalogTask: Task<Void, Never>?
    private var remoteWorkspaceState: WorkspaceRuntimeState?
    private var remoteCatalogState: RemoteSessionCatalogSnapshot?

    /// Source: `events.schema.ts:hostFrameSchema`. A single list reload folds
    /// batches of related host increments into the host-authoritative snapshot.
    /// Source: RC8 `WorkspaceBrowser.sanitizeSearchQuery`. `String.UTF16View`
    /// matches the JavaScript wire length model and the boundary adjustment
    /// prevents a dangling high surrogate from reaching `session.search`.
    static func sanitizeSearchQuery(_ value: String) -> String {
        let withoutNul = value.replacingOccurrences(of: "\u{0000}", with: "")
        let units = Array(withoutNul.utf16)
        guard units.count > 500 else { return withoutNul }
        var end = 500
        if end < units.count,
           (0xD800...0xDBFF).contains(units[end - 1]),
           (0xDC00...0xDFFF).contains(units[end]) {
            end -= 1
        }
        return String(decoding: units.prefix(end), as: UTF16.self)
    }

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
        remoteWorkspaceTask?.cancel()
        remoteCatalogTask?.cancel()
    }

    func bind(
        workspaceRuntime: WorkspaceRuntime,
        eventRuntime: RemoteEventRuntime,
        generation: RemoteConnectionGeneration
    ) {
        refreshTask?.cancel()
        stopObservingHostEvents()
        remoteWorkspaceTask?.cancel()
        remoteCatalogTask?.cancel()
        remoteWorkspaceState = nil
        remoteCatalogState = nil
        phase = .loading

        remoteWorkspaceTask = Task { [weak self] in
            do {
                try await workspaceRuntime.start(generation: generation)
                let snapshots = await workspaceRuntime.snapshots()
                for await state in snapshots {
                    guard !Task.isCancelled else { return }
                    self?.remoteWorkspaceState = state
                    self?.publishRemoteBrowserState()
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error.localizedDescription)
            }
        }

        remoteCatalogTask = Task { [weak self] in
            do {
                _ = try await eventRuntime.open()
                let snapshots = await eventRuntime.catalogs()
                for await state in snapshots {
                    guard !Task.isCancelled else { return }
                    self?.remoteCatalogState = state
                    if state == nil {
                        self?.phase = .loading
                    } else {
                        self?.publishRemoteBrowserState()
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func publishRemoteBrowserState() {
        guard let workspaceState = remoteWorkspaceState,
              let catalogState = remoteCatalogState,
              workspaceState.generation == catalogState.generation
        else { return }
        let old = snapshot
        snapshot = Snapshot(
            workspaces: workspaceState.items.map(WorkspaceSummaryDTO.init(remote:)),
            sessions: catalogState.items.map(SessionSummaryDTO.init(remote:)),
            archivedSessionIDs: Set(workspaceState.archivedSessionIDs),
            selectedSessionID: old.selectedSessionID,
            selectedWorkspaceID: old.selectedWorkspaceID
        )
        phase = .ready
    }

    func refresh(using apis: HarnessAPIs) {
        refreshTask?.cancel()
        phase = .loading
        refreshTask = Task { [weak self] in
            do {
                async let workspaceResponse = apis.workspaces.list()
                async let sessionResponse = apis.sessions.list()
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
    func observeHostEvents(at endpoint: URL, using apis: HarnessAPIs, diagnostics: HostDiagnosticRecorder) {
        eventTask?.cancel()
        let client = SSEClient(baseURL: endpoint)
        eventTask = Task { [weak self] in
            let stream = await client.reconnectingStream(.host)
            do {
                for try await frame in stream {
                    await diagnostics.recordSSEActivity()
                    self?.receiveHostEvent(frame, using: apis)
                }
            } catch is CancellationError {
                return
            } catch {
                await diagnostics.recordRPCError(error)
                // A finite reconnect policy can only surface after exhaustion;
                // lifecycle ownership still replaces this stream on endpoint change.
            }
        }
    }

    /// Applies a server-request already accepted by the verified Host carrier.
    /// The notification itself is not a partial browser snapshot: it only
    /// schedules a full `workspace.list` + `session.list` authority refresh.
    func receiveHostEvent(_ frame: RPCServerRequest, using apis: HarnessAPIs) {
        guard Self.browserAffectingHostMethods.contains(frame.method) else { return }
        scheduleRefresh(using: apis)
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
        remoteWorkspaceTask?.cancel()
        remoteWorkspaceTask = nil
        remoteCatalogTask?.cancel()
        remoteCatalogTask = nil
        remoteWorkspaceState = nil
        remoteCatalogState = nil
        searchQuery = ""
        remoteSearch = .idle
    }

    /// Source: `WorkspaceBrowser.tsx:SEARCH_DEBOUNCE_MS` and
    /// `session-search.ts:SESSION_SEARCH_RESULT_LIMIT`. The store owns request
    /// cancellation and stale result suppression; the view only binds text.
    func search(query: String, using controller: SessionController?) {
        let normalized = Self.sanitizeSearchQuery(query).trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !normalized.isEmpty else {
            remoteSearch = .idle
            return
        }
        remoteSearch = RemoteSearch(query: normalized, status: .loading, items: [], hasMore: false)
        guard let controller else {
            remoteSearch = RemoteSearch(query: normalized, status: .failed, items: [], hasMore: false)
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let response = try await controller.search(query: normalized)
                guard !Task.isCancelled,
                      self?.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
                else { return }
                self?.remoteSearch = RemoteSearch(
                    query: normalized,
                    status: .ready,
                    items: response.items.map(SessionSearchItemDTO.init(remote:)),
                    hasMore: response.hasMore
                )
            } catch {
                guard !Task.isCancelled,
                      self?.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
                else { return }
                self?.remoteSearch = RemoteSearch(query: normalized, status: .failed, items: [], hasMore: false)
            }
        }
    }

    private func scheduleRefresh(using apis: HarnessAPIs) {
        eventRefreshTask?.cancel()
        eventRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refresh(using: apis)
        }
    }

    /// Source: RC8 `workspaces/service.ts:recentWorkspace`. This is a pure
    /// projection over the current Host baselines: a workspace with the most
    /// recently updated accounted session wins; an empty account falls back to
    /// its creation instant; equal timestamps intentionally retain Host list
    /// order by updating only on a strict improvement.
    static func recentWorkspaceID(in snapshot: Snapshot) -> String? {
        let sessionsByID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.sessionId, $0) })
        var selected: String?
        var selectedTime = -Double.infinity
        for workspace in snapshot.workspaces {
            let sessionTime = workspace.sessionIds.compactMap { sessionsByID[$0]?.updatedAt }.max()
            let creationTime = Self.workspaceCreationFormatter.date(from: workspace.createdAt)?.timeIntervalSince1970 ?? -Double.infinity
            let candidateTime = sessionTime ?? creationTime
            if selected == nil || candidateTime > selectedTime {
                selected = workspace.workspaceId
                selectedTime = candidateTime
            }
        }
        return selected
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

    func applyAgentPresetSelection(sessionID: String, agentPreset: String) {
        guard let index = snapshot.sessions.firstIndex(where: { $0.sessionId == sessionID }) else { return }
        let current = snapshot.sessions[index]
        var sessions = snapshot.sessions
        sessions[index] = SessionSummaryDTO(
            sessionId: current.sessionId,
            updatedAt: current.updatedAt,
            running: current.running,
            blank: current.blank,
            pendingInteraction: current.pendingInteraction,
            parentSessionId: current.parentSessionId,
            origin: current.origin,
            cwd: current.cwd,
            agentPreset: agentPreset,
            projections: current.projections
        )
        snapshot = Snapshot(
            workspaces: snapshot.workspaces,
            sessions: sessions,
            archivedSessionIDs: snapshot.archivedSessionIDs,
            selectedSessionID: snapshot.selectedSessionID,
            selectedWorkspaceID: snapshot.selectedWorkspaceID
        )
    }

    func applySessionRename(sessionID: String, value: RemoteSessionRenameValue) {
        guard let index = snapshot.sessions.firstIndex(where: { $0.sessionId == sessionID }) else { return }
        let current = snapshot.sessions[index]
        guard value.seq.rawValue > (current.projections?.asOfSeq ?? -1) else { return }

        var values = current.projections?.values ?? [:]
        values["title"] = .string(value.title)
        var sessions = snapshot.sessions
        sessions[index] = SessionSummaryDTO(
            sessionId: current.sessionId,
            updatedAt: current.updatedAt,
            running: current.running,
            blank: current.blank,
            pendingInteraction: current.pendingInteraction,
            parentSessionId: current.parentSessionId,
            origin: current.origin,
            cwd: current.cwd,
            agentPreset: current.agentPreset,
            projections: .init(asOfSeq: value.seq.rawValue, values: values)
        )
        snapshot = Snapshot(
            workspaces: snapshot.workspaces,
            sessions: sessions,
            archivedSessionIDs: snapshot.archivedSessionIDs,
            selectedSessionID: snapshot.selectedSessionID,
            selectedWorkspaceID: snapshot.selectedWorkspaceID
        )
    }

    /// Snapshot-only projection of the locked official resident fixture. It uses
    /// the same list-RPC DTOs as production and never participates in Host I/O.
    func loadSnapshotFixtureWorkspace(
        primarySessionTitle: String = "Fixture 历史会话",
        primarySessionAgentPreset: String? = nil
    ) {
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
                agentPreset: primarySessionAgentPreset,
                projections: projection(primarySessionTitle)
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

    /// Snapshot-only mirror of the locked RC8 jobs capture. Its selected summary
    /// is the Host durable title/preset projection rendered in the paired
    /// official `jobs-expanded-*` scenes; transcript/jobs remain in the separate
    /// NativeSessionStore fixture.
    func loadSnapshotJobsFixtureWorkspace() {
        loadSnapshotFixtureWorkspace(
            primarySessionTitle: OfficialUISpec.Text.fixtureJobsSessionTitle,
            primarySessionAgentPreset: "standard"
        )
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
