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
    /// Host-owned home path announced by the authenticated rc.1 `$events.ready` frame.
    /// It is generation-scoped and cleared on disconnect/restart.
    @Published private(set) var hostHome: String?
    /// Host capability reported by rc.1 `session/canOpenWorkspacePath`.
    /// The async result is accepted only for the currently bound Remote generation.
    @Published private(set) var canOpenWorkspacePath = false
    /// Snapshot exports normally have no Host. This opt-in exists only for a
    /// recorded official state that includes path-open capability; production never sets it.
    private let snapshotCanOpenProjectPath: Bool
    /// The recorded RC8 Deliverables capture selects the session at a wide
    /// viewport, then shrinks to 780px while retaining the user's explicit
    /// narrow-sidebar expansion. Production has no snapshot override.
    private let snapshotSidebarNarrowExpanded: Bool
    private let releaseFeaturePolicy: NativeReleaseFeaturePolicy

    var canOpenProjectPath: Bool {
        canOpenWorkspacePath || snapshotCanOpenProjectPath
    }

    enum WorkspaceManagementDialog: Equatable {
        case workspaceRename(workspaceID: String, title: String)
        case sessionRename(sessionID: String, title: String)
        case workspaceDelete(workspaceID: String, title: String)
    }

    @Published var workspaceManagementDialog: WorkspaceManagementDialog?
    @Published var userVisibleError: String?

    let workspaceStore: NativeWorkspaceStore
    let sessionStore: NativeSessionStore
    let settingsStore: NativeSettingsStore
    let credentialStore: NativeCredentialStore
    let modelDirectoryStore: NativeModelDirectoryStore
    let modelDiscoveryStore: NativeModelDiscoveryStore
    let agentPresetStore: NativeAgentPresetStore
    @Published var settingsPresented = false
    /// Window-resident native counterparts of RC8's contribution ledgers.
    /// They deliberately outlive individual SwiftUI root-view assignments.
    let conversationViewRegistry = NativeConversationViewRegistry()
    let conversationHeaderContributions = NativeConversationHeaderContributionRegistry()
    let workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog
    /// Snapshot-only presentation affordance; never part of Host session truth.
    let jobsPopoverInitiallyOpen: Bool
    /// Optional capture-only locale for Jobs; production uses the system locale.
    let jobsSnapshotLanguageCode: String?
    private var controllers: HarnessControllers?
    private var workspaceRuntime: WorkspaceRuntime?
    private var eventRuntime: RemoteEventRuntime?
    private var sessionControlRuntime: SessionControlRuntime?
    private var modelCatalogRepository: ModelCatalogRepository?
    private var settingsRepository: SettingsRepository?
    private var credentialRepository: CredentialRepository?
    private var remoteGeneration: RemoteConnectionGeneration?
    private var selectedToolObservation: AnyCancellable?
    private var observedEndpoint: URL?
    /// Source: RC8 `WorkspaceRuntime.connecting`. Concurrent New Session
    /// requests for one workspace share the same blank lookup/create work.
    private let blankConnectionCoordinator = NativeWorkspaceConnectionCoordinator()
    /// Cancels navigation from stale blank-connect completions after a newer
    /// selection, endpoint switch, or no-workspace clear.
    private var newSessionGeneration = 0

    init(
        mode: NativeAppShell.PresentationMode = .welcome,
        workspaceStore: NativeWorkspaceStore? = nil,
        sessionStore: NativeSessionStore? = nil,
        settingsStore: NativeSettingsStore? = nil,
        credentialStore: NativeCredentialStore? = nil,
        modelDirectoryStore: NativeModelDirectoryStore? = nil,
        modelDiscoveryStore: NativeModelDiscoveryStore? = nil,
        agentPresetStore: NativeAgentPresetStore? = nil,
        workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog = .none,
        jobsPopoverInitiallyOpen: Bool = false,
        jobsSnapshotLanguageCode: String? = nil,
        snapshotCanOpenProjectPath: Bool = false,
        snapshotSidebarNarrowExpanded: Bool = false,
        releaseFeaturePolicy: NativeReleaseFeaturePolicy = .releaseCandidate
    ) {
        self.mode = mode
        self.workspaceStore = workspaceStore ?? NativeWorkspaceStore()
        self.sessionStore = sessionStore ?? NativeSessionStore()
        self.settingsStore = settingsStore ?? NativeSettingsStore()
        self.credentialStore = credentialStore ?? NativeCredentialStore()
        self.modelDirectoryStore = modelDirectoryStore ?? NativeModelDirectoryStore()
        self.modelDiscoveryStore = modelDiscoveryStore ?? NativeModelDiscoveryStore()
        self.agentPresetStore = agentPresetStore ?? NativeAgentPresetStore()
        self.workspaceSnapshotDialog = workspaceSnapshotDialog
        self.jobsPopoverInitiallyOpen = jobsPopoverInitiallyOpen
        self.jobsSnapshotLanguageCode = jobsSnapshotLanguageCode
        self.snapshotCanOpenProjectPath = snapshotCanOpenProjectPath
        self.snapshotSidebarNarrowExpanded = snapshotSidebarNarrowExpanded
        self.releaseFeaturePolicy = releaseFeaturePolicy
        self.detailsVisible = self.sessionStore.selectedToolCallID != nil
        if releaseFeaturePolicy.permits(.trajectoryTab) {
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
        }
        if releaseFeaturePolicy.permits(.subagentCatalogAction) {
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
        // A ready HostConnection is generation-scoped even when the loopback
        // endpoint is reused. Tear down the previous streams before binding the
        // new authoritative Remote generation.
        let previousWorkspaceRuntime = workspaceRuntime
        let previousEventRuntime = eventRuntime
        let previousControlRuntime = sessionControlRuntime
        Task {
            await previousWorkspaceRuntime?.stop()
            await previousEventRuntime?.close()
            await previousControlRuntime?.invalidate()
        }

        let controllers = HarnessControllers(remote: connection.context.remote)
        let workspaceRuntime = WorkspaceRuntime(controller: controllers.workspaces)
        let eventRuntime = RemoteEventRuntime(channel: connection.context.events, sessions: controllers.sessions)
        let sessionControlRuntime = SessionControlRuntime(
            controller: controllers.sessions,
            generation: connection.context.events.generation
        )
        let modelCatalogRepository = ModelCatalogRepository(controller: controllers.sessions)
        let settingsRepository = SettingsRepository(source: controllers.settings)
        let credentialRepository = CredentialRepository(source: controllers.credentials)
        self.controllers = controllers
        self.workspaceRuntime = workspaceRuntime
        self.eventRuntime = eventRuntime
        self.sessionControlRuntime = sessionControlRuntime
        self.modelCatalogRepository = modelCatalogRepository
        self.settingsRepository = settingsRepository
        self.credentialRepository = credentialRepository
        remoteGeneration = connection.context.events.generation
        hostHome = connection.context.events.ready.host.home
        canOpenWorkspacePath = false
        let pathCapabilityGeneration = connection.context.events.generation
        Task { [weak self] in
            let canOpen = (try? await controllers.sessions.canOpenWorkspacePath()) ?? false
            guard let self, self.remoteGeneration == pathCapabilityGeneration else { return }
            self.canOpenWorkspacePath = canOpen
        }
        sessionStore.bindCommandService(SessionCommandService(controller: controllers.sessions))
        sessionStore.bindSessionController(controllers.sessions)
        sessionStore.bindModelCatalogRepository(modelCatalogRepository)
        sessionStore.bindGoalController(controllers.goals)
        sessionStore.bindSubagentController(controllers.subagents)
        sessionStore.bindMessageFeedbackController(controllers.messageFeedback)
        sessionStore.bindEventRuntime(eventRuntime)
        sessionStore.bindControlRuntime(sessionControlRuntime)

        observedEndpoint = connection.endpoint

        workspaceStore.bind(
            workspaceRuntime: workspaceRuntime,
            eventRuntime: eventRuntime,
            generation: connection.context.events.generation
        )

        Task { [weak self] in await self?.agentPresetStore.refresh(using: controllers.agentPresets) }
        if settingsPresented {
            settingsStore.load(using: settingsRepository)
            Task { [weak self] in await self?.modelDirectoryStore.refresh(using: controllers.llm) }
        }

        // The conversation store remains on its transitional facade until its
        // journal/control binding is migrated in the next cut. The facade uses
        // the authenticated cookie session above, so no unauthenticated parallel
        // client is created.
        if let selectedSessionID = sessionStore.selectedSessionID {
            sessionStore.open(
                sessionID: selectedSessionID,
                endpoint: connection.endpoint,
                sessionCWD: sessionCWD(for: selectedSessionID),
                sessionRuntime: SessionRuntime(
                    controller: controllers.sessions,
                    generation: connection.context.events.generation,
                    address: .session(sessionID: selectedSessionID)
                )
            )
        }
    }

    func setSidebarViewportNarrow(_ isNarrow: Bool) {
        var updated = sidebarLayout
        updated.setNarrow(isNarrow)
        // Equivalent to RC8's user toggle after AppFrame's narrow breakpoint
        // computed the rail. It is present only in an evidence fixture.
        if isNarrow, snapshotSidebarNarrowExpanded {
            updated.setCollapsed(false)
        }
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
        blankConnectionCoordinator.cancelAll()
        let previousWorkspaceRuntime = workspaceRuntime
        let previousEventRuntime = eventRuntime
        let previousControlRuntime = sessionControlRuntime
        Task {
            await previousWorkspaceRuntime?.stop()
            await previousEventRuntime?.close()
            await previousControlRuntime?.invalidate()
        }
        controllers = nil
        workspaceRuntime = nil
        eventRuntime = nil
        sessionControlRuntime = nil
        let previousModelCatalogRepository = modelCatalogRepository
        modelCatalogRepository = nil
        settingsRepository = nil
        credentialRepository = nil
        Task { await previousModelCatalogRepository?.invalidate() }
        remoteGeneration = nil
        observedEndpoint = nil
        hostHome = nil
        canOpenWorkspacePath = false
        workspaceStore.detachHost()
        sessionStore.disconnect()
        settingsStore.load(using: nil)
        Task { [weak self] in await self?.modelDirectoryStore.refresh(using: nil) }
        modelDiscoveryStore.dismiss()
        Task { [weak self] in await self?.agentPresetStore.refresh(using: nil) }
        settingsPresented = false
        mode = .welcome
        closeDetails()
    }

    func openSettings() {
        settingsPresented = true
        settingsStore.load(using: settingsRepository)
        Task { [weak self] in await self?.modelDirectoryStore.refresh(using: self?.controllers?.llm) }
        Task { [weak self] in await self?.agentPresetStore.refresh(using: self?.controllers?.agentPresets) }
    }

    func closeSettings() {
        settingsPresented = false
    }

    /// The General Appearance row emits only a typed official preference. The
    /// view itself has no transport access; on failure, a fresh Host descriptor
    /// remains authoritative and no local durable preference is manufactured.
    func refreshModelDirectory() async {
        await modelDirectoryStore.refresh(using: controllers?.llm)
    }

    func discoverModels(_ request: LLMDiscoverModelsRequest) async {
        await modelDiscoveryStore.discover(request, using: controllers?.llm)
    }

    func adoptDiscoveredModels(
        _ candidates: [LLMDiscoveredModelDTO],
        selectedIDs: Set<String>,
        for provider: LLMProviderDTO
    ) async -> Bool {
        guard let settingsAPI = settingsRepository else { return false }
        do {
            let adopted = try await settingsStore.adoptDiscoveredModels(
                candidates,
                selectedIDs: selectedIDs,
                for: provider,
                using: settingsAPI
            )
            if adopted { await modelDirectoryStore.refresh(using: controllers?.llm) }
            return adopted
        } catch {
            return false
        }
    }

    func refreshAgentPresets() async {
        await agentPresetStore.refresh(using: controllers?.agentPresets)
    }

    func readAgentPreset(_ agentPreset: String) async -> Bool {
        await agentPresetStore.read(agentPreset: agentPreset, using: controllers?.agentPresets)
    }

    func openAgentPresetDocument(_ agentPreset: String) async -> Bool {
        await agentPresetStore.openDocument(agentPreset: agentPreset, using: controllers?.agentPresets)
    }

    func copyAgentPreset(_ request: AgentPresetCopyRequest) async -> Bool {
        await agentPresetStore.copy(request, using: controllers?.agentPresets)
    }

    func removeAgentPreset(_ agentPreset: String) async -> Bool {
        await agentPresetStore.remove(agentPreset: agentPreset, using: controllers?.agentPresets)
    }

    /// RC8 seat selection is legal only while the Host projects this session as
    /// blank. Running-session histories cannot be recomposed locally.
    func selectAgentPreset(sessionID: String, presetID: String) async -> Bool {
        guard let agentPresets = controllers?.agentPresets,
              workspaceStore.snapshot.sessions.contains(where: { $0.sessionId == sessionID && $0.blank })
        else { return false }
        let selected = await agentPresetStore.select(sessionID: sessionID, agentPreset: presetID, using: agentPresets)
        if selected { workspaceStore.applyAgentPresetSelection(sessionID: sessionID, agentPreset: presetID) }
        return selected
    }

    func selectAgentPresetDefault(_ preset: AgentPresetEntryDTO) async -> Bool {
        guard let settingsAPI = settingsRepository else { return false }
        do {
            try await settingsStore.selectAgentPresetDefault(preset, using: settingsAPI)
            guard settingsStore.agentPresetDefault.current == preset.id else { return false }
            await agentPresetStore.refresh(using: controllers?.agentPresets)
            return agentPresetStore.presets.contains(where: { $0.id == preset.id && $0.isDefault })
        } catch {
            return false
        }
    }

    func selectThemePreference(_ preference: CoreThemePreference) {
        guard let api = settingsRepository else { return }
        Task { [weak self] in
            do {
                try await self?.settingsStore.selectThemePreference(preference, using: api)
                guard self?.settingsStore.themePreference.current == preference else { return }
                switch preference {
                case .light: NSApp.appearance = NSAppearance(named: NSAppearance.Name.aqua)
                case .dark: NSApp.appearance = NSAppearance(named: NSAppearance.Name.darkAqua)
                case .system: NSApp.appearance = nil
                }
            } catch {
                self?.settingsStore.load(using: api)
            }
        }
    }

    /// Presents no local success state: card drafts are cleared by their view
    /// only after this method returns the Host-accepted namespace update.
    func savePluginCardDraft(_ draft: NativePluginCardDraft) async -> Bool {
        guard let api = settingsRepository else { return false }
        do {
            return try await settingsStore.savePluginCardDraft(draft, using: api)
        } catch {
            return false
        }
    }

    func refreshCredential(_ reference: String) async {
        await refreshCredentials([reference])
    }

    func refreshCredentials(_ references: [String]) async {
        await credentialStore.refresh(refs: references, using: credentialRepository)
    }

    func setCredential(reference: String, value: String) async -> Bool {
        await credentialStore.set(reference: reference, value: value, using: credentialRepository)
    }

    func unsetCredential(reference: String) async -> Bool {
        await credentialStore.unset(reference: reference, using: credentialRepository)
    }

    func selectSession(_ sessionID: String, workspaceID: String?) {
        let didSwitchSession = sessionStore.selectedSessionID != sessionID
        workspaceStore.select(sessionID: sessionID, workspaceID: workspaceID)
        if let observedEndpoint {
            let runtime: SessionRuntime?
            if let controllers, let remoteGeneration {
                runtime = SessionRuntime(
                    controller: controllers.sessions,
                    generation: remoteGeneration,
                    address: .session(sessionID: sessionID)
                )
            } else {
                runtime = nil
            }
            sessionStore.open(
                sessionID: sessionID,
                endpoint: observedEndpoint,
                sessionCWD: sessionCWD(for: sessionID),
                sessionRuntime: runtime
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
        guard let controllers, let endpoint = observedEndpoint else { return }
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
                let sessionID = try await connectWorkspace(target, using: controllers.sessions)
                guard !Task.isCancelled,
                      newSessionGeneration == generation,
                      observedEndpoint == endpoint
                else { return }
                selectSession(sessionID, workspaceID: target)
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
    private func connectWorkspace(_ workspaceID: String, using sessions: any SessionControllerAPI) async throws -> String {
        try await blankConnectionCoordinator.connect(workspaceID: workspaceID) { [weak self] in
            guard let self else { throw CancellationError() }
            guard self.workspaceStore.snapshot.workspaces.contains(where: { $0.workspaceId == workspaceID }) else {
                throw URLError(.fileDoesNotExist)
            }
            if let reusable = NativeWorkspaceBlankSessionReuse.reusableSessionID(
                workspaceID: workspaceID,
                in: self.workspaceStore.snapshot
            ) {
                return reusable
            }
            return try await sessions.create(.init(workspaceId: workspaceID)).sessionId
        }
    }

    /// Source: `workspace.schema.ts:workspaceRenameRequestSchema`.
    func renameWorkspace(_ workspaceID: String, title: String) async throws {
        guard let workspaceRuntime else { throw URLError(.notConnectedToInternet) }
        _ = try await workspaceRuntime.rename(workspaceID: workspaceID, title: title)
    }

    /// Source: `workspace.schema.ts:workspaceDeleteRequestSchema`.
    func deleteWorkspace(_ workspaceID: String) async throws {
        guard let workspaceRuntime else { throw URLError(.notConnectedToInternet) }
        _ = try await workspaceRuntime.delete(workspaceID: workspaceID)
    }

    /// Source: `workspace.schema.ts:workspaceInsertBeforeRequestSchema`.
    func moveWorkspace(_ workspaceID: String, beforeWorkspaceID: String?) async throws {
        guard let workspaceRuntime else { throw URLError(.notConnectedToInternet) }
        _ = try await workspaceRuntime.insertBefore(workspaceID: workspaceID, beforeWorkspaceID: beforeWorkspaceID)
    }

    /// Source: `workspace.schema.ts:workspaceInsertSessionBeforeRequestSchema`.
    func moveSession(_ sessionID: String, in workspaceID: String, beforeSessionID: String?) async throws {
        guard let workspaceRuntime else { throw URLError(.notConnectedToInternet) }
        _ = try await workspaceRuntime.insertSessionBefore(
            workspaceID: workspaceID,
            sessionID: sessionID,
            beforeSessionID: beforeSessionID
        )
    }

    /// Source: `sessions.schema.ts:sessionRenameRequestSchema`.
    func renameSession(_ sessionID: String, title: String) async throws {
        guard let controllers else { throw URLError(.notConnectedToInternet) }
        let renamed = try await controllers.sessions.rename(sessionID: sessionID, title: title)
        guard !Task.isCancelled else { return }
        workspaceStore.applySessionRename(sessionID: sessionID, value: renamed)
    }

    /// Source: `sessions.schema.ts:sessionForkRequestSchema`.
    func forkSession(_ sessionID: String) {
        guard let controllers else { return }
        let workspaceID = workspaceStore.snapshot.workspaces.first { $0.sessionIds.contains(sessionID) }?.workspaceId
        Task { [weak self] in
            guard let self else { return }
            do {
                let forked = try await controllers.sessions.fork(sessionID: sessionID, atSeq: nil)
                guard !Task.isCancelled else { return }
                selectSession(forked.sessionId, workspaceID: workspaceID)
            } catch {
                DispatchQueue.main.async { self.userVisibleError = String(describing: error) }
            }
        }
    }

    /// Source: `workspace.schema.ts:workspaceArchiveSessionRequestSchema`.
    func archiveSession(_ sessionID: String) {
        guard let workspaceRuntime else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await workspaceRuntime.archiveSession(sessionID: sessionID)
            } catch {
                DispatchQueue.main.async { self.userVisibleError = String(describing: error) }
            }
        }
    }

    func searchSessions(_ query: String) {
        workspaceStore.search(query: query, using: controllers?.sessions)
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
        guard let workspaceRuntime else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await workspaceRuntime.create(path: url.path)
            } catch {
                DispatchQueue.main.async { self.userVisibleError = String(describing: error) }
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
    private var settingsWindow: NSWindow?

    init(presentation: NativeShellPresentation) {
        self.presentation = presentation
        super.init(
            sidebar: Self.sidebar(for: presentation, collapsed: presentation.sidebarLayout.isCollapsed),
            conversation: NativeConversationColumn(
                mode: presentation.mode,
                selectedWorkspaceTitle: Self.selectedWorkspaceTitle(for: presentation),
                sessionSnapshot: presentation.workspaceStore.snapshot,
                sessionStore: presentation.sessionStore,
                agentPresetStore: presentation.agentPresetStore,
                selectAgentPreset: { [weak presentation] sessionID, presetID in
                    guard let presentation else { return false }
                    return await presentation.selectAgentPreset(sessionID: sessionID, presetID: presetID)
                },
                jobsPopoverInitiallyOpen: presentation.jobsPopoverInitiallyOpen,
                jobsLanguageCode: presentation.jobsSnapshotLanguageCode,
                openSession: { sessionID in
                    presentation.selectSession(sessionID, workspaceID: Self.workspaceID(for: sessionID, in: presentation))
                },
                canOpenProjectPath: presentation.canOpenProjectPath,
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
                agentPresetStore: presentation.agentPresetStore,
                selectAgentPreset: { [weak presentation] sessionID, presetID in
                    guard let presentation else { return false }
                    return await presentation.selectAgentPreset(sessionID: sessionID, presetID: presetID)
                },
                jobsPopoverInitiallyOpen: presentation.jobsPopoverInitiallyOpen,
                jobsLanguageCode: presentation.jobsSnapshotLanguageCode,
                openSession: { [weak self] sessionID in
                    guard let self else { return }
                    let current = self.presentation
                    current.selectSession(sessionID, workspaceID: Self.workspaceID(for: sessionID, in: current))
                },
                canOpenProjectPath: presentation.canOpenProjectPath,
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
        synchronizeSettingsWindow()
    }

    private func synchronizeSettingsWindow() {
        guard presentation.settingsPresented else {
            settingsWindow?.close()
            settingsWindow = nil
            return
        }
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let root = NativeSettingsRoot(
            store: presentation.settingsStore,
            retry: { [weak presentation] in presentation?.openSettings() },
            close: { [weak presentation] in presentation?.closeSettings() },
            selectTheme: { [weak presentation] preference in
                presentation?.selectThemePreference(preference)
            },
            credentialStore: presentation.credentialStore,
            modelDirectoryStore: presentation.modelDirectoryStore,
            modelDiscoveryStore: presentation.modelDiscoveryStore,
            agentPresetStore: presentation.agentPresetStore,
            refreshModelDirectory: { [weak presentation] in
                await presentation?.refreshModelDirectory()
            },
            discoverModels: { [weak presentation] request in
                await presentation?.discoverModels(request)
            },
            adoptDiscoveredModels: { [weak presentation] candidates, selectedIDs, provider in
                guard let presentation else { return false }
                return await presentation.adoptDiscoveredModels(candidates, selectedIDs: selectedIDs, for: provider)
            },
            refreshAgentPresets: { [weak presentation] in
                await presentation?.refreshAgentPresets()
            },
            readAgentPreset: { [weak presentation] agentPreset in
                guard let presentation else { return false }
                return await presentation.readAgentPreset(agentPreset)
            },
            openAgentPresetDocument: { [weak presentation] agentPreset in
                guard let presentation else { return false }
                return await presentation.openAgentPresetDocument(agentPreset)
            },
            copyAgentPreset: { [weak presentation] request in
                guard let presentation else { return false }
                return await presentation.copyAgentPreset(request)
            },
            removeAgentPreset: { [weak presentation] agentPreset in
                guard let presentation else { return false }
                return await presentation.removeAgentPreset(agentPreset)
            },
            selectAgentPresetDefault: { [weak presentation] preset in
                guard let presentation else { return false }
                return await presentation.selectAgentPresetDefault(preset)
            },
            refreshCredential: { [weak presentation] reference in
                await presentation?.refreshCredential(reference)
            },
            refreshCredentials: { [weak presentation] references in
                await presentation?.refreshCredentials(references)
            },
            setCredential: { [weak presentation] reference, value in
                guard let presentation else { return false }
                return await presentation.setCredential(reference: reference, value: value)
            },
            unsetCredential: { [weak presentation] reference in
                guard let presentation else { return false }
                return await presentation.unsetCredential(reference: reference)
            },
            savePluginCard: { [weak presentation] draft in
                guard let presentation else { return false }
                return await presentation.savePluginCardDraft(draft)
            }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-general", key: "title", language: "en") ?? ""
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
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
            hostHome: presentation.hostHome,
            settingsPresented: presentation.settingsPresented,
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
            onOpenSettings: { presentation.openSettings() }
        )
    }

    private static func details(for presentation: NativeShellPresentation) -> NativeDetailsView {
        NativeDetailsView(
            sessionStore: presentation.sessionStore,
            close: { presentation.closeDetails() }
        )
    }
}

extension NativeShellController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === settingsWindow else { return }
        settingsWindow = nil
        if presentation.settingsPresented { presentation.closeSettings() }
    }
}

/// Shared divider policy used by the production `NSSplitViewController` and
/// deterministic T5.2 regression tests. It mirrors the official columns
/// constraints rather than relying on AppKit's implicit proportional resize.
struct NativeSplitLayoutPolicy {
    /// Mirrors RC8 AppFrame's ResizeObserver contract: column concessions are
    /// recomputed on a real frame-width change, but never reapplied during the
    /// nested same-width AppKit layout pass caused by divider placement.
    static func needsViewportReconciliation(
        hasAppliedLayout: Bool,
        lastResolvedViewport: CGFloat?,
        viewport: CGFloat
    ) -> Bool {
        guard viewport > 0 else { return false }
        return !hasAppliedLayout || lastResolvedViewport != viewport
    }

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
    /// The official AppFrame re-solves columns whenever its own frame changes.
    /// Keep that viewport identity separately so AppKit relayout from divider
    /// placement does not reapply a solver result over a same-width user drag.
    private var lastResolvedViewport: CGFloat?
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
        guard NativeSplitLayoutPolicy.needsViewportReconciliation(
            hasAppliedLayout: hasAppliedInitialLayout,
            lastResolvedViewport: lastResolvedViewport,
            viewport: splitView.bounds.width
        ) else { return }
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
        applyLayout(force: true)
    }

    private func applyLayout(force: Bool = false) {
        guard isViewLoaded else { return }
        let viewport = splitView.bounds.width
        guard force || NativeSplitLayoutPolicy.needsViewportReconciliation(
            hasAppliedLayout: hasAppliedInitialLayout,
            lastResolvedViewport: lastResolvedViewport,
            viewport: viewport
        ) else { return }
        let columns = OfficialColumnLayout.resolve(
            viewport: viewport,
            sidebarPreference: renderedSidebarCollapsed ? 0 : sidebarPreference,
            detailsPreference: detailsVisible ? detailsPreference : 0
        )
        // Record before moving dividers: those moves cause a nested AppKit
        // layout pass, which must not turn a one-shot viewport reconciliation
        // into a feedback loop.
        lastResolvedViewport = viewport
        detailsItem.isCollapsed = columns.details == 0
        splitView.setPosition(columns.sidebar, ofDividerAt: 0)
        if columns.details > 0, splitViewItems.count > 2 {
            splitView.setPosition(viewport - columns.details, ofDividerAt: 1)
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
