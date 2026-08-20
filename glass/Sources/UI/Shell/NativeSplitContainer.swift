import AppKit
import Combine
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// Source: RC8 `packages/client/ui-layout/src/client/stores.ts` (`LayoutState`,
/// `toggleSidebar`, and `setNarrow`). A narrow viewport derives a collapsed
/// rail by default. Its manual re-expansion is an override only: it never
/// rewrites the wide-window collapsed preference or dragged width.
struct NativeSidebarLayoutState: Equatable {
    private(set) var isNarrow = false
    private(set) var narrowExpanded = false
    private(set) var widePreferenceCollapsed = false

    var isCollapsed: Bool {
        isNarrow ? !narrowExpanded : widePreferenceCollapsed
    }

    mutating func setNarrow(_ isNarrow: Bool) {
        guard self.isNarrow != isNarrow else { return }
        self.isNarrow = isNarrow
        narrowExpanded = false
    }

    mutating func setCollapsed(_ collapsed: Bool) {
        if isNarrow {
            narrowExpanded = !collapsed
        } else {
            widePreferenceCollapsed = collapsed
        }
    }
}

/// RC8 `WorkspaceRuntime.connectWorkspace` only reuses a blank session from
/// the requested workspace's canonical cwd. The pure predicate keeps this
/// Host-authoritative condition independently testable from task coalescing.
enum NativeWorkspaceBlankSessionReuse {
    static func reusableSessionID(
        workspaceID: String,
        in snapshot: NativeWorkspaceStore.Snapshot
    ) -> String? {
        guard let workspace = snapshot.workspaces.first(where: { $0.workspaceId == workspaceID }) else {
            return nil
        }
        return snapshot.sessions.first(where: { session in
            session.blank
                && session.cwd == workspace.path
                && workspace.sessionIds.contains(session.sessionId)
                && !snapshot.archivedSessionIDs.contains(session.sessionId)
        })?.sessionId
    }
}

/// Main-actor presentation ownership for the native shell. It deliberately
/// holds only window-local presentation state; Host workspace/session truth
/// stays in `NativeWorkspaceStore`.
@MainActor
final class NativeShellPresentation: ObservableObject {
    @Published var mode: NativeAppShell.PresentationMode
    @Published var sidebarPreference: CGFloat = OfficialUISpec.Layout.sidebarDefault
    @Published var detailsPreference: CGFloat = OfficialUISpec.Layout.detailsDefault
    @Published private(set) var sidebarLayout = NativeSidebarLayoutState()
    @Published var detailsVisible = false
    /// Host-owned RC8 display context. It is fetched only after the endpoint has
    /// passed the build-trust gate and cleared on disconnect/restart.
    @Published private(set) var hostDescription: HostDescribeResponse?

    enum WorkspaceManagementDialog: Equatable {
        case workspaceRename(workspaceID: String, title: String)
        case sessionRename(sessionID: String, title: String)
        case workspaceDelete(workspaceID: String, title: String)
    }

    @Published var workspaceManagementDialog: WorkspaceManagementDialog?

    let workspaceStore: NativeWorkspaceStore
    let sessionStore: NativeSessionStore
    /// Window-resident native counterparts of RC8's contribution ledgers.
    /// They deliberately outlive individual SwiftUI root-view assignments.
    let conversationViewRegistry = NativeConversationViewRegistry()
    let conversationHeaderContributions = NativeConversationHeaderContributionRegistry()
    let workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog
    /// Snapshot-only presentation affordance; never part of Host session truth.
    let jobsPopoverInitiallyOpen: Bool
    /// Optional capture-only locale for Jobs; production uses the system locale.
    let jobsSnapshotLanguageCode: String?
    private var apis: HarnessAPIs?
    private var selectedToolObservation: AnyCancellable?
    private var observedEndpoint: URL?
    /// Source: RC8 `WorkspaceRuntime.connecting`. Concurrent New Session
    /// requests for one workspace share the same blank lookup/create work.
    private var blankConnectionTasks: [String: Task<String, Error>] = [:]
    /// Cancels navigation from stale blank-connect completions after a newer
    /// selection, endpoint switch, or no-workspace clear.
    private var newSessionGeneration = 0

    init(
        mode: NativeAppShell.PresentationMode = .welcome,
        workspaceStore: NativeWorkspaceStore? = nil,
        sessionStore: NativeSessionStore? = nil,
        workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog = .none,
        jobsPopoverInitiallyOpen: Bool = false,
        jobsSnapshotLanguageCode: String? = nil
    ) {
        self.mode = mode
        self.workspaceStore = workspaceStore ?? NativeWorkspaceStore()
        self.sessionStore = sessionStore ?? NativeSessionStore()
        self.workspaceSnapshotDialog = workspaceSnapshotDialog
        self.jobsPopoverInitiallyOpen = jobsPopoverInitiallyOpen
        self.jobsSnapshotLanguageCode = jobsSnapshotLanguageCode
        self.detailsVisible = self.sessionStore.selectedToolCallID != nil
        do {
            // Source: RC8 `ui-trajectory/src/client/index.ts`: the trajectory
            // contribution is a real `conversation.view` tab, ordered after
            // Chat and backed by its target-specific inspection snapshot.
            try conversationViewRegistry.register(
                id: "trajectory",
                order: 10,
                label: OfficialUISpec.Text.trajectory
            ) { context in
                AnyView(NativeTrajectoryView(sessionStore: context.sessionStore))
            }
        } catch {
            assertionFailure("Built-in trajectory view registration must be unique: \(error)")
        }
        do {
            // Source: RC8 `ui-subagent/src/client/index.ts:60-68`: direct-child
            // catalog is a session-header action at order 10.
            try conversationHeaderContributions.register(
                slot: .actions,
                id: "subagent-catalog",
                order: 10
            ) { context in
                AnyView(NativeSubagentCatalogHeaderAction(sessionStore: context.sessionStore, openSession: context.openSession))
            }
        } catch {
            assertionFailure("Built-in subagent catalog registration must be unique: \(error)")
        }
        switch workspaceSnapshotDialog {
        case .none:
            workspaceManagementDialog = nil
        case .workspaceRename:
            workspaceManagementDialog = .workspaceRename(workspaceID: "fx-ws-fixture", title: "fixture")
        case .sessionRename:
            workspaceManagementDialog = .sessionRename(sessionID: "fx-alpha", title: "Fixture 历史会话")
        case .workspaceDelete:
            workspaceManagementDialog = .workspaceDelete(workspaceID: "fx-ws-fixture", title: "fixture")
        }
        selectedToolObservation = self.sessionStore.$selectedToolCallID.sink { [weak self] callID in
            guard let self else { return }
            if callID == nil {
                closeDetails()
            } else {
                openDetails()
            }
        }
    }

    /// Called only after `HarnessHostController` has verified host.describe on
    /// the pinned bundled Host. The browser obtains its truth from list RPCs
    /// and the official Host SSE stream, never from a web surface.
    func connectVerifiedHost(_ connection: HostConnection) {
        guard observedEndpoint != connection.endpoint else { return }
        // Preserve the user-selected session across an owned Host restart. The
        // new port means all old HTTP/WebSocket carriers are invalid; reopen()
        // creates only fresh typed facades and uses the Host's official
        // read-only cold-resume path before observing the new mux endpoint.
        let selectedSessionID = sessionStore.selectedSessionID
        newSessionGeneration &+= 1
        blankConnectionTasks.values.forEach { $0.cancel() }
        blankConnectionTasks.removeAll()
        workspaceStore.stopObservingHostEvents()
        let apis = HarnessAPIs(
            baseURL: connection.endpoint,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(connection.build)),
            diagnostics: connection.diagnostics
        )
        self.apis = apis
        observedEndpoint = connection.endpoint
        Task { [weak self] in
            do {
                let description = try await apis.host.describe()
                guard !Task.isCancelled, self?.observedEndpoint == connection.endpoint else { return }
                self?.hostDescription = description
            } catch {
                // The endpoint has passed its transport-level verification. A
                // later description refresh is permitted; absence only disables
                // display abbreviation and never invents a local home path.
                guard self?.observedEndpoint == connection.endpoint else { return }
                self?.hostDescription = nil
            }
        }
        workspaceStore.refresh(using: apis)
        workspaceStore.observeHostEvents(at: connection.endpoint, using: apis, diagnostics: connection.diagnostics)
        if let selectedSessionID {
            sessionStore.open(
                sessionID: selectedSessionID,
                using: apis.sessions,
                endpoint: connection.endpoint,
                hostPathAPI: apis.host,
                goalAPI: apis.commands,
                subagentCatalogAPI: apis.subagents,
                subagentContinuationAPI: apis.subagents,
                sessionCWD: sessionCWD(for: selectedSessionID)
            )
        }
    }

    func setSidebarViewportNarrow(_ isNarrow: Bool) {
        var updated = sidebarLayout
        updated.setNarrow(isNarrow)
        guard updated != sidebarLayout else { return }
        sidebarLayout = updated
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        var updated = sidebarLayout
        updated.setCollapsed(collapsed)
        guard updated != sidebarLayout else { return }
        sidebarLayout = updated
    }

    /// Source: RC8 `createLayoutStore.closeDetails/openDetails`. Closing writes
    /// the zero-width preference; reopening restores the contract default rather
    /// than an old dragged width.
    func closeDetails() {
        detailsVisible = false
        detailsPreference = 0
    }

    func openDetails() {
        if detailsPreference == 0 {
            detailsPreference = OfficialUISpec.Layout.detailsDefault
        }
        detailsVisible = true
    }

    func disconnectHost() {
        newSessionGeneration &+= 1
        blankConnectionTasks.values.forEach { $0.cancel() }
        blankConnectionTasks.removeAll()
        apis = nil
        observedEndpoint = nil
        hostDescription = nil
        workspaceStore.detachHost()
        sessionStore.disconnect()
        mode = .welcome
        closeDetails()
    }

    func selectSession(_ sessionID: String, workspaceID: String?) {
        let didSwitchSession = sessionStore.selectedSessionID != sessionID
        workspaceStore.select(sessionID: sessionID, workspaceID: workspaceID)
        if let apis, let observedEndpoint {
            sessionStore.open(
                sessionID: sessionID,
                using: apis.sessions,
                endpoint: observedEndpoint,
                hostPathAPI: apis.host,
                goalAPI: apis.commands,
                subagentCatalogAPI: apis.subagents,
                subagentContinuationAPI: apis.subagents,
                sessionCWD: sessionCWD(for: sessionID)
            )
        }
        mode = .conversation
        synchronizeDetailsAfterSessionSelection(didSwitchSession: didSwitchSession)
    }

    /// Source: RC8 `AppFrame` closes the details panel when the current session
    /// changes, even if the newly resident session contains a tool selection.
    /// Staying in the same session may surface its selected tool normally.
    func synchronizeDetailsAfterSessionSelection(didSwitchSession: Bool) {
        guard !didSwitchSession, sessionStore.selectedToolCallID != nil else {
            closeDetails()
            return
        }
        openDetails()
    }

    private func sessionCWD(for sessionID: String) -> String? {
        workspaceStore.snapshot.sessions.first(where: { $0.sessionId == sessionID })?.cwd
    }

    /// Source: RC8 `workspaces/service.ts:startSession` and
    /// `connectWorkspace`. Explicit workspace wins, then the selected session's
    /// workspace, then the Host-order stable recent-workspace projection. A
    /// missing target clears only selection; it does not create an unscoped
    /// synthetic session or disconnect the Host.
    func createSession(in workspaceID: String?) {
        guard let apis, let endpoint = observedEndpoint else { return }
        let snapshot = workspaceStore.snapshot
        let currentWorkspaceID = snapshot.selectedSessionID.flatMap { selectedID in
            snapshot.workspaces.first(where: { $0.sessionIds.contains(selectedID) })?.workspaceId
        }
        let target = workspaceID ?? currentWorkspaceID ?? NativeWorkspaceStore.recentWorkspaceID(in: snapshot)
        guard let target else {
            newSessionGeneration &+= 1
            workspaceStore.select(sessionID: nil, workspaceID: nil)
            sessionStore.clearActiveSelection()
            mode = .welcome
            closeDetails()
            return
        }

        newSessionGeneration &+= 1
        let generation = newSessionGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let sessionID = try await connectWorkspace(target, using: apis)
                guard !Task.isCancelled,
                      newSessionGeneration == generation,
                      observedEndpoint == endpoint
                else { return }
                selectSession(sessionID, workspaceID: target)
                workspaceStore.refresh(using: apis)
            } catch {
                // RC8 treats a rejected blank connection as non-fatal: keep the
                // current selection usable and wait for the next Host authority.
            }
        }
    }

    /// Source: RC8 `WorkspaceRuntime.connectWorkspace`. Only a blank session
    /// that is both accounted by the workspace and has the workspace canonical
    /// cwd is reusable; archived blanks are intentionally invisible and cannot
    /// be opened. A create is coalesced per workspace until it settles.
    private func connectWorkspace(_ workspaceID: String, using apis: HarnessAPIs) async throws -> String {
        if let task = blankConnectionTasks[workspaceID] {
            return try await task.value
        }
        let task = Task<String, Error> { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            guard let workspace = self.workspaceStore.snapshot.workspaces.first(where: { $0.workspaceId == workspaceID }) else {
                throw URLError(.fileDoesNotExist)
            }
            if let reusable = NativeWorkspaceBlankSessionReuse.reusableSessionID(
                workspaceID: workspaceID,
                in: self.workspaceStore.snapshot
            ) {
                return reusable
            }
            return try await apis.sessions.create(workspaceID: workspaceID).sessionId
        }
        blankConnectionTasks[workspaceID] = task
        defer { blankConnectionTasks[workspaceID] = nil }
        return try await task.value
    }

    /// Source: `workspace.schema.ts:workspaceRenameRequestSchema`.
    func renameWorkspace(_ workspaceID: String, title: String) async throws {
        guard let apis else { throw URLError(.notConnectedToInternet) }
        _ = try await apis.workspaces.rename(workspaceID: workspaceID, title: title)
        guard !Task.isCancelled else { return }
        workspaceStore.refresh(using: apis)
    }

    /// Source: `workspace.schema.ts:workspaceDeleteRequestSchema`.
    func deleteWorkspace(_ workspaceID: String) async throws {
        guard let apis else { throw URLError(.notConnectedToInternet) }
        _ = try await apis.workspaces.delete(workspaceID: workspaceID)
        guard !Task.isCancelled else { return }
        workspaceStore.refresh(using: apis)
    }

    /// Source: `workspace.schema.ts:workspaceInsertBeforeRequestSchema`.
    func moveWorkspace(_ workspaceID: String, beforeWorkspaceID: String?) async throws {
        guard let apis else { throw URLError(.notConnectedToInternet) }
        _ = try await apis.workspaces.insertBefore(workspaceID: workspaceID, beforeWorkspaceID: beforeWorkspaceID)
        guard !Task.isCancelled else { return }
        workspaceStore.refresh(using: apis)
    }

    /// Source: `workspace.schema.ts:workspaceInsertSessionBeforeRequestSchema`.
    func moveSession(_ sessionID: String, in workspaceID: String, beforeSessionID: String?) async throws {
        guard let apis else { throw URLError(.notConnectedToInternet) }
        _ = try await apis.workspaces.insertSessionBefore(workspaceID: workspaceID, sessionID: sessionID, beforeSessionID: beforeSessionID)
        guard !Task.isCancelled else { return }
        workspaceStore.refresh(using: apis)
    }

    /// Source: `sessions.schema.ts:sessionRenameRequestSchema`.
    func renameSession(_ sessionID: String, title: String) async throws {
        guard let apis else { throw URLError(.notConnectedToInternet) }
        _ = try await apis.sessions.rename(sessionID: sessionID, title: title)
        guard !Task.isCancelled else { return }
        workspaceStore.refresh(using: apis)
    }

    /// Source: `sessions.schema.ts:sessionForkRequestSchema`.
    func forkSession(_ sessionID: String) {
        guard let apis else { return }
        let workspaceID = workspaceStore.snapshot.workspaces.first { $0.sessionIds.contains(sessionID) }?.workspaceId
        Task { [weak self] in
            guard let self else { return }
            do {
                let forked = try await apis.sessions.fork(sessionID: sessionID)
                guard !Task.isCancelled else { return }
                workspaceStore.refresh(using: apis)
                selectSession(forked.sessionId, workspaceID: workspaceID)
            } catch {
                // Fork rejection leaves the Host projection untouched.
            }
        }
    }

    /// Source: `workspace.schema.ts:workspaceArchiveSessionRequestSchema`.
    func archiveSession(_ sessionID: String) {
        guard let apis else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await apis.workspaces.archiveSession(sessionID: sessionID)
                guard !Task.isCancelled else { return }
                workspaceStore.refresh(using: apis)
            } catch {
                // Archive is dialog-free in the official browser; the Host owns failures.
            }
        }
    }

    func searchSessions(_ query: String) {
        workspaceStore.search(query: query, using: apis?.sessions)
    }

    func presentWorkspaceRename(workspaceID: String, title: String) {
        workspaceManagementDialog = .workspaceRename(workspaceID: workspaceID, title: title)
    }

    func presentSessionRename(sessionID: String, title: String) {
        workspaceManagementDialog = .sessionRename(sessionID: sessionID, title: title)
    }

    func presentWorkspaceDelete(workspaceID: String, title: String) {
        workspaceManagementDialog = .workspaceDelete(workspaceID: workspaceID, title: title)
    }

    func dismissWorkspaceManagementDialog() {
        workspaceManagementDialog = nil
    }

    /// Source: `workspace.schema.ts:workspaceCreateRequestSchema`. macOS uses
    /// a native directory panel rather than a browser-mediated file picker.
    func addWorkspace() {
        guard let apis else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await apis.workspaces.create(path: url.path)
                guard !Task.isCancelled else { return }
                workspaceStore.refresh(using: apis)
            } catch {
                // The Host owns validation of adopted directories; no local
                // workspace state is invented when adoption is refused.
            }
        }
    }
}

/// The real AppKit root controller. Both the running application and the CI
/// snapshot window use this controller directly, so NSSplitViewController owns
/// the complete view-controller tree rather than being embedded in SwiftUI.
@MainActor
final class NativeShellController: NativeSplitViewController {
    private let presentation: NativeShellPresentation
    private var presentationObservation: AnyCancellable?

    init(presentation: NativeShellPresentation) {
        self.presentation = presentation
        super.init(
            sidebar: Self.sidebar(for: presentation, collapsed: presentation.sidebarLayout.isCollapsed),
            conversation: NativeConversationColumn(
                mode: presentation.mode,
                selectedWorkspaceTitle: Self.selectedWorkspaceTitle(for: presentation),
                sessionSnapshot: presentation.workspaceStore.snapshot,
                sessionStore: presentation.sessionStore,
                jobsPopoverInitiallyOpen: presentation.jobsPopoverInitiallyOpen,
                jobsLanguageCode: presentation.jobsSnapshotLanguageCode,
                openSession: { sessionID in
                    presentation.selectSession(sessionID, workspaceID: Self.workspaceID(for: sessionID, in: presentation))
                },
                viewRegistry: presentation.conversationViewRegistry,
                headerContributions: presentation.conversationHeaderContributions
            ),
            details: Self.details(for: presentation),
            sidebarPreference: presentation.sidebarPreference,
            detailsPreference: presentation.detailsPreference,
            sidebarCollapsed: presentation.sidebarLayout.isCollapsed,
            detailsVisible: presentation.detailsVisible && presentation.mode != .welcome,
            sidebarPreferenceChanged: { width in
                guard abs(presentation.sidebarPreference - width) > 0.5 else { return }
                presentation.sidebarPreference = width
            },
            detailsPreferenceChanged: { width in
                guard abs(presentation.detailsPreference - width) > 0.5 else { return }
                presentation.detailsPreference = width
            }
        )
        presentationObservation = presentation.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.renderPresentation() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLayout() {
        super.viewDidLayout()
        let isNarrow = view.bounds.width < OfficialUISpec.Layout.sidebarAutoCollapse
        presentation.setSidebarViewportNarrow(isNarrow)
        if presentation.sidebarLayout.isCollapsed != renderedSidebarCollapsed {
            renderPresentation()
        }
    }

    /// Call after a window assigns final bounds (particularly important for
    /// off-screen snapshot windows whose controller first lays out at zero).
    func refreshForCurrentViewport() {
        renderPresentation()
    }

    private static func selectedWorkspaceTitle(for presentation: NativeShellPresentation) -> String? {
        guard let workspaceID = presentation.workspaceStore.snapshot.selectedWorkspaceID else { return nil }
        return presentation.workspaceStore.snapshot.workspaces.first { $0.workspaceId == workspaceID }?.title
    }

    /// RC8 hierarchy navigation reopens the Host session through the ordinary
    /// session-selection path. A subagent may be ungrouped, so the workspace id
    /// is optional rather than inferred from its breadcrumb title.
    private static func workspaceID(for sessionID: String, in presentation: NativeShellPresentation) -> String? {
        presentation.workspaceStore.snapshot.workspaces.first { workspace in
            workspace.sessionIds.contains(sessionID)
        }?.workspaceId
    }

    private func renderPresentation() {
        let isNarrow = isViewLoaded && view.bounds.width < OfficialUISpec.Layout.sidebarAutoCollapse
        presentation.setSidebarViewportNarrow(isNarrow)
        let collapsed = presentation.sidebarLayout.isCollapsed
        update(
            sidebar: Self.sidebar(for: presentation, collapsed: collapsed),
            conversation: NativeConversationColumn(
                mode: presentation.mode,
                selectedWorkspaceTitle: Self.selectedWorkspaceTitle(for: presentation),
                sessionSnapshot: presentation.workspaceStore.snapshot,
                sessionStore: presentation.sessionStore,
                jobsPopoverInitiallyOpen: presentation.jobsPopoverInitiallyOpen,
                jobsLanguageCode: presentation.jobsSnapshotLanguageCode,
                openSession: { [weak self] sessionID in
                    guard let self else { return }
                    let current = self.presentation
                    current.selectSession(sessionID, workspaceID: Self.workspaceID(for: sessionID, in: current))
                },
                viewRegistry: presentation.conversationViewRegistry,
                headerContributions: presentation.conversationHeaderContributions
            ),
            details: Self.details(for: presentation),
            sidebarPreference: presentation.sidebarPreference,
            detailsPreference: presentation.detailsPreference,
            sidebarCollapsed: collapsed,
            detailsVisible: presentation.detailsVisible && presentation.mode != .welcome
        )
        updateDocumentTitle()
    }

    /// Source: RC8 `ui-renderer/DocumentTitle.tsx`. The native titlebar remains
    /// visually hidden, but standard AppKit document title state stays aligned
    /// with the selected durable Host session for system restoration/accessibility.
    private func updateDocumentTitle() {
        view.window?.title = Self.documentTitle(for: presentation)
    }

    private static func documentTitle(for presentation: NativeShellPresentation) -> String {
        guard let sessionID = presentation.workspaceStore.snapshot.selectedSessionID,
              let title = presentation.workspaceStore.snapshot.sessions.first(where: { $0.sessionId == sessionID })?.displayTitle
        else { return OfficialUISpec.Text.sidebarFallbackBrand }
        return "\(title) — \(OfficialUISpec.Text.sidebarFallbackBrand)"
    }

    private static func sidebar(
        for presentation: NativeShellPresentation,
        collapsed: Bool
    ) -> NativeSidebarView {
        NativeSidebarView(
            workspaceStore: presentation.workspaceStore,
            hostHome: presentation.hostDescription?.home,
            collapsed: collapsed,
            setCollapsed: { presentation.setSidebarCollapsed($0) },
            workspaceActions: WorkspaceBrowserView.Actions(
                addWorkspace: { presentation.addWorkspace() },
                createSession: { presentation.createSession(in: $0) },
                selectSession: { presentation.selectSession($0, workspaceID: $1) },
                forkSession: { presentation.forkSession($0) },
                archiveSession: { presentation.archiveSession($0) },
                searchSessions: { presentation.searchSessions($0) },
                presentWorkspaceRename: { presentation.presentWorkspaceRename(workspaceID: $0, title: $1) },
                presentWorkspaceDelete: { presentation.presentWorkspaceDelete(workspaceID: $0, title: $1) },
                presentSessionRename: { presentation.presentSessionRename(sessionID: $0, title: $1) },
                commitWorkspaceRename: { workspaceID, title in
                    try await presentation.renameWorkspace(workspaceID, title: title)
                },
                commitWorkspaceDelete: { workspaceID in
                    try await presentation.deleteWorkspace(workspaceID)
                },
                commitSessionRename: { sessionID, title in
                    try await presentation.renameSession(sessionID, title: title)
                },
                moveWorkspace: { workspaceID, beforeWorkspaceID in
                    try await presentation.moveWorkspace(workspaceID, beforeWorkspaceID: beforeWorkspaceID)
                },
                moveSession: { sessionID, workspaceID, beforeSessionID in
                    try await presentation.moveSession(sessionID, in: workspaceID, beforeSessionID: beforeSessionID)
                }
            ),
            workspaceSnapshotDialog: presentation.workspaceSnapshotDialog,
            onNewSession: { presentation.createSession(in: presentation.workspaceStore.snapshot.selectedWorkspaceID) },
            onOpenSettings: {}
        )
    }

    private static func details(for presentation: NativeShellPresentation) -> NativeDetailsView {
        NativeDetailsView(
            sessionStore: presentation.sessionStore,
            close: { presentation.closeDetails() }
        )
    }
}

/// Shared divider policy used by the production `NSSplitViewController` and
/// deterministic T5.2 regression tests. It mirrors the official columns
/// constraints rather than relying on AppKit's implicit proportional resize.
struct NativeSplitLayoutPolicy {
    static func sidebarDividerPosition(proposed: CGFloat, collapsed: Bool) -> CGFloat {
        if collapsed { return OfficialUISpec.Layout.sidebarCollapsed }
        return min(max(proposed, OfficialUISpec.Layout.sidebarMinimum), OfficialUISpec.Layout.sidebarMaximum)
    }

    static func detailsDividerPosition(
        proposed: CGFloat,
        viewport: CGFloat,
        sidebarWidth: CGFloat
    ) -> CGFloat {
        let detailsWidth = viewport - proposed
        let constrained = min(max(detailsWidth, OfficialUISpec.Layout.detailsMinimum), OfficialUISpec.Layout.detailsMaximum)
        let availableDetails = viewport - sidebarWidth - OfficialUISpec.Layout.centerMinimum
        guard availableDetails >= OfficialUISpec.Layout.detailsMinimum else { return viewport }
        return viewport - min(constrained, availableDetails)
    }
}

/// AppKit owns resize dividers and child-controller containment. SwiftUI is
/// confined to the official-spec content surfaces inside the three panes.
@MainActor
class NativeSplitViewController: NSSplitViewController {
    private let sidebarHost: OfficialSidebarHostController
    private let conversationHost: NSHostingController<NativeConversationColumn>
    private let detailsHost: TransparentHostingController<NativeDetailsView>
    private let sidebarItem: NSSplitViewItem
    private let conversationItem: NSSplitViewItem
    private let detailsItem: NSSplitViewItem
    private let sidebarPreferenceChanged: (CGFloat) -> Void
    private let detailsPreferenceChanged: (CGFloat) -> Void

    private var sidebarPreference: CGFloat
    private var detailsPreference: CGFloat
    private(set) var renderedSidebarCollapsed: Bool
    private var detailsVisible: Bool
    private var hasAppliedInitialLayout = false

    init(
        sidebar: NativeSidebarView,
        conversation: NativeConversationColumn,
        details: NativeDetailsView,
        sidebarPreference: CGFloat,
        detailsPreference: CGFloat,
        sidebarCollapsed: Bool,
        detailsVisible: Bool,
        sidebarPreferenceChanged: @escaping (CGFloat) -> Void,
        detailsPreferenceChanged: @escaping (CGFloat) -> Void
    ) {
        sidebarHost = OfficialSidebarHostController(rootView: sidebar)
        conversationHost = NSHostingController(rootView: conversation)
        detailsHost = TransparentHostingController(rootView: details)
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        conversationItem = NSSplitViewItem(viewController: conversationHost)
        detailsItem = NSSplitViewItem(inspectorWithViewController: detailsHost)
        self.sidebarPreference = sidebarPreference
        self.detailsPreference = detailsPreference
        self.sidebarPreferenceChanged = sidebarPreferenceChanged
        self.detailsPreferenceChanged = detailsPreferenceChanged
        renderedSidebarCollapsed = sidebarCollapsed
        self.detailsVisible = detailsVisible
        super.init(nibName: nil, bundle: nil)

        sidebarItem.canCollapse = false
        conversationItem.canCollapse = false
        detailsItem.canCollapse = true
        detailsItem.collapseBehavior = .useConstraints
        addSplitViewItem(sidebarItem)
        addSplitViewItem(conversationItem)
        addSplitViewItem(detailsItem)
        splitView.dividerStyle = .thin
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !hasAppliedInitialLayout else { return }
        applyLayout()
    }

    func update(
        sidebar: NativeSidebarView,
        conversation: NativeConversationColumn,
        details: NativeDetailsView,
        sidebarPreference: CGFloat,
        detailsPreference: CGFloat,
        sidebarCollapsed: Bool,
        detailsVisible: Bool
    ) {
        sidebarHost.update(rootView: sidebar)
        conversationHost.rootView = conversation
        detailsHost.rootView = details

        let behaviorChanged = renderedSidebarCollapsed != sidebarCollapsed
            || self.detailsVisible != detailsVisible
        self.sidebarPreference = sidebarPreference
        self.detailsPreference = detailsPreference
        renderedSidebarCollapsed = sidebarCollapsed
        self.detailsVisible = detailsVisible
        if behaviorChanged { hasAppliedInitialLayout = false }
        applyLayout()
    }

    private func applyLayout() {
        guard isViewLoaded, splitView.bounds.width > 0 else { return }
        let columns = OfficialColumnLayout.resolve(
            viewport: splitView.bounds.width,
            sidebarPreference: renderedSidebarCollapsed ? 0 : sidebarPreference,
            detailsPreference: detailsVisible ? detailsPreference : 0
        )
        detailsItem.isCollapsed = columns.details == 0
        splitView.setPosition(columns.sidebar, ofDividerAt: 0)
        if columns.details > 0, splitViewItems.count > 2 {
            splitView.setPosition(splitView.bounds.width - columns.details, ofDividerAt: 1)
        }
        hasAppliedInitialLayout = true
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0:
            let constrained = NativeSplitLayoutPolicy.sidebarDividerPosition(
                proposed: proposedPosition,
                collapsed: renderedSidebarCollapsed
            )
            if !renderedSidebarCollapsed, abs(constrained - sidebarPreference) > 0.5 {
                sidebarPreference = constrained
                sidebarPreferenceChanged(constrained)
            }
            return constrained
        case 1:
            let sidebarWidth = renderedSidebarCollapsed ? OfficialUISpec.Layout.sidebarCollapsed : sidebarPreference
            let constrained = NativeSplitLayoutPolicy.detailsDividerPosition(
                proposed: proposedPosition,
                viewport: splitView.bounds.width,
                sidebarWidth: sidebarWidth
            )
            let detailsWidth = splitView.bounds.width - constrained
            if detailsWidth > 0, abs(detailsWidth - detailsPreference) > 0.5 {
                detailsPreference = detailsWidth
                detailsPreferenceChanged(detailsWidth)
            }
            return constrained
        default:
            return proposedPosition
        }
    }
}

/// Application root that keeps `NSSplitViewController` and the official Modal
/// overlay as siblings. An overlay must never be added to `NSSplitView` itself:
/// its child views participate in divider layout rather than covering the frame.
@MainActor
final class NativeShellRootController: NSViewController {
    private let shellController: NativeShellController
    private let managementDialogHost: TransparentHostingController<NativeWorkspaceManagementDialogOverlay>

    init(presentation: NativeShellPresentation) {
        shellController = NativeShellController(presentation: presentation)
        managementDialogHost = TransparentHostingController(
            rootView: NativeWorkspaceManagementDialogOverlay(presentation: presentation)
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        view = root

        addChild(shellController)
        addChild(managementDialogHost)
        let shell = shellController.view
        let overlay = managementDialogHost.view
        shell.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shell)
        view.addSubview(overlay, positioned: .above, relativeTo: shell)
        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shell.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shell.topAnchor.constraint(equalTo: view.topAnchor),
            shell.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func refreshForCurrentViewport() {
        shellController.refreshForCurrentViewport()
    }
}

/// A transparent AppKit bridge is required because the default SwiftUI hosting
/// view owns an opaque backing surface, which would otherwise replace the split
/// view with black instead of compositing the official Modal mask over it.
private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

final class TransparentHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        let transparentView = TransparentHostingView(rootView: rootView)
        transparentView.wantsLayer = true
        transparentView.layer?.isOpaque = false
        transparentView.layer?.backgroundColor = NSColor.clear.cgColor
        view = transparentView
    }
}

/// Native full-window rendering of the locked official `Modal` primitive used
/// by the workspace browser. It replaces a macOS sheet because the official
/// WebUI dialog is a centered card over the complete three-column frame.
private struct NativeWorkspaceManagementDialogOverlay: View {
    @ObservedObject var presentation: NativeShellPresentation

    @State private var renameDraft = ""
    @State private var operationError: String?
    @State private var submitting = false

    var body: some View {
        ZStack {
            if let dialog = presentation.workspaceManagementDialog {
                OfficialUISpec.Token.modalMask
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }

                dialogCard(dialog)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .allowsHitTesting(presentation.workspaceManagementDialog != nil)
        .onAppear { synchronizeDraft() }
        .onChange(of: presentation.workspaceManagementDialog) { _, _ in
            synchronizeDraft()
        }
    }

    @ViewBuilder
    private func dialogCard(_ dialog: NativeShellPresentation.WorkspaceManagementDialog) -> some View {
        switch dialog {
        case .workspaceRename(_, let title):
            renameCard(
                title: OfficialUISpec.Text.renameWorkspaceTitle,
                fieldLabel: OfficialUISpec.Text.workspaceName,
                originalTitle: title,
                confirm: { submitWorkspaceRename() }
            )
        case .sessionRename(_, let title):
            renameCard(
                title: OfficialUISpec.Text.renameSessionTitle,
                fieldLabel: OfficialUISpec.Text.sessionName,
                originalTitle: title,
                confirm: { submitSessionRename() }
            )
        case .workspaceDelete(_, let title):
            deleteCard(workspaceTitle: title)
        }
    }

    private func renameCard(
        title: String,
        fieldLabel: String,
        originalTitle: String,
        confirm: @escaping () -> Void
    ) -> some View {
        modalSurface(title: title, height: 208) {
            NativeSelectAllTextField(
                text: $renameDraft,
                fieldLabel: fieldLabel,
                selectionID: title + originalTitle,
                disabled: submitting,
                onSubmit: confirm
            )
            .frame(height: OfficialUISpec.Layout.modalRenameInputHeight)
            .padding(.top, OfficialUISpec.Layout.modalBodyTopMargin)
            .padding(.horizontal, OfficialUISpec.Layout.modalContentHorizontalPadding)

            if let operationError {
                Text(operationError)
                    .font(OfficialUISpec.Typography.xxs12)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    .padding(.top, OfficialUISpec.Spacing.p8)
                    .padding(.horizontal, OfficialUISpec.Layout.modalContentHorizontalPadding)
            }
        } footer: {
            HStack(spacing: OfficialUISpec.Layout.modalFooterGap) {
                Spacer(minLength: 0)
                modalActionButton(
                    OfficialUISpec.Text.cancel,
                    width: 74,
                    emphasis: .outline,
                    disabled: submitting,
                    action: dismiss
                )
                modalActionButton(
                    OfficialUISpec.Text.rename,
                    width: 81,
                    emphasis: .primary,
                    disabled: submitting || renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == originalTitle,
                    action: confirm
                )
            }
        }
    }

    private func deleteCard(workspaceTitle: String) -> some View {
        modalSurface(title: OfficialUISpec.Text.deleteWorkspace, height: 230) {
            Text(OfficialUISpec.Text.deleteWorkspaceDescription(name: workspaceTitle))
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .lineSpacing(0)
                .frame(maxWidth: .infinity, minHeight: OfficialUISpec.Geometry.px66, alignment: .topLeading)
                .padding(.horizontal, OfficialUISpec.Layout.modalContentHorizontalPadding)

            // The official Modal receives a conditional (empty) body, whose
            // `.body` margin remains in layout even when no status/error text is visible.
            Color.clear
                .frame(height: OfficialUISpec.Layout.modalBodyTopMargin)
        } footer: {
            HStack(spacing: OfficialUISpec.Layout.modalFooterGap) {
                Spacer(minLength: 0)
                modalActionButton(
                    OfficialUISpec.Text.cancel,
                    width: 74,
                    emphasis: .outline,
                    disabled: submitting,
                    action: dismiss
                )
                modalActionButton(
                    OfficialUISpec.Text.deleteWorkspace,
                    width: 141,
                    emphasis: .danger,
                    disabled: submitting,
                    action: submitWorkspaceDelete
                )
            }
        }
    }

    private func modalSurface<Content: View, Footer: View>(
        title: String,
        height: CGFloat,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: OfficialUISpec.Layout.modalInterSectionGap) {
            VStack(spacing: OfficialUISpec.Spacing.p0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(OfficialUISpec.Typography.baseStrong16)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .frame(height: OfficialUISpec.Geometry.px24, alignment: .leading)
                    Spacer(minLength: 0)
                    Button(action: dismiss) {
                        OfficialAssetImage(name: "icon-close", template: true)
                            .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                            .frame(
                                width: OfficialUISpec.Layout.modalCloseControl,
                                height: OfficialUISpec.Layout.modalCloseControl
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(OfficialUISpec.Text.close)
                    .disabled(submitting)
                }
                .padding(.leading, OfficialUISpec.Layout.modalHeaderLeading)
                .padding(.top, OfficialUISpec.Layout.modalHeaderTop)
                .padding(.trailing, OfficialUISpec.Layout.modalHeaderTrailing)
                .padding(.bottom, OfficialUISpec.Layout.modalHeaderBottom)

                content()
            }

            HStack(spacing: OfficialUISpec.Spacing.p0) {
                footer()
            }
            .padding(.horizontal, OfficialUISpec.Layout.modalContentHorizontalPadding)
        }
        .padding(.bottom, OfficialUISpec.Layout.modalCardBottomPadding)
        .frame(
            width: OfficialUISpec.Layout.modalCardOuterWidth,
            height: height,
            alignment: .top
        )
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.modalCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.modalCardCornerRadius, style: .continuous)
                .stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Layout.modalCardBorder)
        }
        .shadow(color: OfficialUISpec.Token.modalMask3, radius: 24, x: 0, y: 12)
    }

    private enum ModalActionEmphasis {
        case outline
        case primary
        case danger
    }

    private func modalActionButton(
        _ title: String,
        width: CGFloat,
        emphasis: ModalActionEmphasis,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(actionBackground(emphasis: emphasis))
                if let border = actionBorder(emphasis: emphasis) {
                    Capsule()
                        .stroke(border, lineWidth: OfficialUISpec.Layout.modalCardBorder)
                }
                Text(title)
                    .font(OfficialUISpec.Typography.s14)
                    .foregroundStyle(actionForeground(emphasis: emphasis))
            }
            .frame(width: width, height: OfficialUISpec.Layout.modalActionButtonHeight)
            .clipShape(Capsule())
            .compositingGroup()
            // Source: Button.module.css:.button:disabled — opacity applies to
            // the complete button, not to separately substituted fill/border tokens.
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .disabled(disabled)
    }

    private func actionForeground(emphasis: ModalActionEmphasis) -> Color {
        switch emphasis {
        case .outline:
            return OfficialUISpec.Token.primary
        case .primary:
            return OfficialUISpec.Token.elevated
        case .danger:
            return OfficialUISpec.Token.errorPrimary
        }
    }

    private func actionBackground(emphasis: ModalActionEmphasis) -> Color {
        switch emphasis {
        case .outline, .danger:
            return Color.clear
        case .primary:
            // Source: design-platform.css:179,191 — button primary fill is
            // the neutral `--dsw-alias-brand-primary`, not DeepSeek blue.
            return OfficialUISpec.Token.primary
        }
    }

    private func actionBorder(emphasis: ModalActionEmphasis) -> Color? {
        switch emphasis {
        case .primary:
            // Source: Button.module.css:.primary — fill only, with no border.
            return nil
        case .outline, .danger:
            return OfficialUISpec.Token.border
        }
    }

    private func synchronizeDraft() {
        operationError = nil
        submitting = false
        switch presentation.workspaceManagementDialog {
        case .workspaceRename(_, let title), .sessionRename(_, let title):
            renameDraft = title
        case .workspaceDelete, .none:
            renameDraft = ""
        }
    }

    private func dismiss() {
        guard !submitting else { return }
        presentation.dismissWorkspaceManagementDialog()
    }

    private func submitWorkspaceRename() {
        guard case .workspaceRename(let workspaceID, let originalTitle)? = presentation.workspaceManagementDialog else { return }
        submit {
            try await presentation.renameWorkspace(
                workspaceID,
                title: renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func submitSessionRename() {
        guard case .sessionRename(let sessionID, _)? = presentation.workspaceManagementDialog else { return }
        submit {
            try await presentation.renameSession(
                sessionID,
                title: renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func submitWorkspaceDelete() {
        guard case .workspaceDelete(let workspaceID, _)? = presentation.workspaceManagementDialog else { return }
        submit {
            try await presentation.deleteWorkspace(workspaceID)
        }
    }

    private func submit(_ operation: @escaping () async throws -> Void) {
        guard !submitting else { return }
        submitting = true
        operationError = nil
        Task {
            do {
                try await operation()
                presentation.dismissWorkspaceManagementDialog()
            } catch {
                operationError = error.localizedDescription
                submitting = false
            }
        }
    }
}

/// Native equivalent of the official rename input's `autoFocus` plus
/// `e.target.select()` behavior in `WorkspaceBrowser.tsx`.
private struct NativeSelectAllTextField: NSViewRepresentable {
    @Binding var text: String
    let fieldLabel: String
    let selectionID: String
    let disabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NativeSelectAllNSTextField {
        let field = NativeSelectAllNSTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 14, weight: .regular)
        field.textColor = NSColor(OfficialUISpec.Token.primary)
        field.backgroundColor = .clear
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = text
        field.setAccessibilityLabel(fieldLabel)
        field.selectionID = selectionID
        return field
    }

    func updateNSView(_ field: NativeSelectAllNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.isEnabled = !disabled
        field.setAccessibilityLabel(fieldLabel)
        if field.selectionID != selectionID {
            field.selectionID = selectionID
            field.selectAllWhenPossible()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSelectAllTextField

        init(parent: NativeSelectAllTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

private final class NativeSelectAllNSTextField: NSTextField {
    var selectionID = ""

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        selectAllWhenPossible()
    }

    func selectAllWhenPossible() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.isEnabled else { return }
            self.window?.makeFirstResponder(self)
            self.currentEditor()?.selectAll(nil)
        }
    }
}
