import Foundation
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// Native rendering of the official `WorkspaceBrowser` hierarchy. Host state is
/// injected from `NativeWorkspaceStore`; this view holds only browser-local
/// expansion and search-input animation state.
struct WorkspaceBrowserView: View {
    @ObservedObject var store: NativeWorkspaceStore
    /// Source: RC8 `host.describe.home`; used only for official display-path abbreviation.
    let hostHome: String?
    let collapsed: Bool
    let requestSidebarExpansion: () -> Void
    let actions: Actions
    let snapshotDialog: SnapshotDialog

    enum SnapshotDialog {
        case none
        case workspaceRename
        case sessionRename
        case workspaceDelete
    }

    struct Actions {
        var addWorkspace: () -> Void = {}
        var createSession: (String?) -> Void = { _ in }
        var selectSession: (String, String?) -> Void = { _, _ in }
        /// Browser-local requests are replaced by `rowActions` so dialogs outlive rows.
        var renameWorkspace: (String, String) -> Void = { _, _ in }
        var deleteWorkspace: (String, String) -> Void = { _, _ in }
        var renameSession: (String, String) -> Void = { _, _ in }
        var forkSession: (String) -> Void = { _ in }
        var archiveSession: (String) -> Void = { _ in }
        var searchSessions: (String) -> Void = { _ in }
        var presentWorkspaceRename: (String, String) -> Void = { _, _ in }
        var presentWorkspaceDelete: (String, String) -> Void = { _, _ in }
        var presentSessionRename: (String, String) -> Void = { _, _ in }
        var commitWorkspaceRename: (String, String) async throws -> Void = { _, _ in }
        var commitWorkspaceDelete: (String) async throws -> Void = { _ in }
        var commitSessionRename: (String, String) async throws -> Void = { _, _ in }
        /// Source: `workspace.insertBefore`; only real workspace group drags call this.
        var moveWorkspace: (String, String?) async throws -> Void = { _, _ in }
        /// Source: `workspace.insertSessionBefore`; only manually ordered real
        /// workspace accounts call this after their local order is committed.
        var moveSession: (String, String, String?) async throws -> Void = { _, _, _ in }
    }

    private struct RenameTarget: Identifiable {
        let id: String
        let title: String
    }

    private struct DeleteTarget: Identifiable {
        let id: String
        let title: String
    }

    /// In-flight RC8 workspace drag state. It is never persisted.
    private struct WorkspaceDrag: Equatable {
        let workspaceID: String
        var over: DropTarget?
    }

    /// In-flight RC8 session drag state. The account key prevents a session
    /// drag from crossing workspace/ungrouped account boundaries.
    private struct SessionDrag: Equatable {
        let accountKey: String
        let sessionID: String
        var over: DropTarget?
    }

    private struct DropTarget: Equatable {
        let id: String
        let half: NativeWorkspaceBrowserOrdering.DropHalf
    }

    @State private var searchExpanded = false
    @State private var expandedWorkspaceIDs: Set<String>
    @State private var workspaceRenameTarget: RenameTarget?
    @State private var sessionRenameTarget: RenameTarget?
    @State private var deleteTarget: DeleteTarget?
    @State private var renameDraft = ""
    @State private var renameError: String?
    @State private var renaming = false
    @State private var deleting = false
    @State private var deleteCommittedID: String?
    @State private var deleteError: String?
    /// Source: RC8 `createWorkspaceViewStore`: new browsers group by workspace
    /// and promote activity in the `updated` ordering mode.
    @State private var sessionGroupMode: NativeWorkspaceBrowserOrdering.SessionGroupMode = .workspace
    @State private var sessionOrderMode: NativeWorkspaceBrowserOrdering.SessionOrderMode = .updated
    /// Browser-local account order is deliberately separate from Host workspace
    /// membership/order. Ungrouped and `updated` reorders never write Host RPCs.
    @State private var sessionOrderByAccount: [String: [String]] = [:]
    /// RC8 compares this account-local timestamp baseline to promote only new
    /// activity while retaining the user-edited order of unaffected sessions.
    @State private var sessionUpdatedAtByAccount: [String: [String: Double]] = [:]
    @State private var workspaceDrag: WorkspaceDrag?
    @State private var sessionDrag: SessionDrag?
    @State private var workspaceDropCommitted = false
    @State private var sessionDropCommitted = false

    init(
        store: NativeWorkspaceStore,
        hostHome: String? = nil,
        collapsed: Bool,
        requestSidebarExpansion: @escaping () -> Void,
        actions: Actions,
        snapshotDialog: SnapshotDialog = .none
    ) {
        self.store = store
        self.hostHome = hostHome
        self.collapsed = collapsed
        self.requestSidebarExpansion = requestSidebarExpansion
        self.actions = actions
        self.snapshotDialog = snapshotDialog
        _expandedWorkspaceIDs = State(initialValue: Set(store.snapshot.selectedWorkspaceID.map { [$0] } ?? []))
        _searchExpanded = State(initialValue: !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        switch snapshotDialog {
        case .none:
            _workspaceRenameTarget = State(initialValue: nil)
            _sessionRenameTarget = State(initialValue: nil)
            _deleteTarget = State(initialValue: nil)
            _renameDraft = State(initialValue: "")
        case .workspaceRename:
            _workspaceRenameTarget = State(initialValue: nil)
            _sessionRenameTarget = State(initialValue: nil)
            _deleteTarget = State(initialValue: nil)
            _renameDraft = State(initialValue: "")
        case .sessionRename:
            _workspaceRenameTarget = State(initialValue: nil)
            _sessionRenameTarget = State(initialValue: nil)
            _deleteTarget = State(initialValue: nil)
            _renameDraft = State(initialValue: "")
        case .workspaceDelete:
            _workspaceRenameTarget = State(initialValue: nil)
            _sessionRenameTarget = State(initialValue: nil)
            _deleteTarget = State(initialValue: nil)
            _renameDraft = State(initialValue: "")
        }
    }

    var body: some View {
        if collapsed {
            WorkspaceBrowserRail(
                requestSidebarExpansion: requestSidebarExpansion,
                addWorkspace: actions.addWorkspace
            )
        } else {
            VStack(spacing: OfficialUISpec.Spacing.p0) {
                sectionHeader
                listArea
            }
            .padding(.trailing, OfficialUISpec.Layout.sidebarInlinePadding)
            .onChange(of: store.searchQuery) { _, value in
                actions.searchSessions(value)
            }
            .onChange(of: store.snapshot.selectedWorkspaceID) { _, workspaceID in
                if let workspaceID { expandedWorkspaceIDs.insert(workspaceID) }
            }
            .onChange(of: store.snapshot.workspaces.map(\.workspaceId)) { _, workspaceIDs in
                guard let deleteCommittedID, !workspaceIDs.contains(deleteCommittedID) else { return }
                deleting = false
                self.deleteCommittedID = nil
                deleteTarget = nil
            }
            .onChange(of: store.snapshot.sessions.map { "\($0.sessionId)|\($0.updatedAt)" }) { _, _ in
                reconcileBrowserLocalOrders()
            }
            .onChange(of: store.snapshot.workspaces.flatMap(\.sessionIds)) { _, _ in
                reconcileBrowserLocalOrders()
            }
            .onChange(of: sessionOrderMode) { _, _ in
                reconcileBrowserLocalOrders(sortUpdatedAccounts: true)
            }
            .onChange(of: sessionGroupMode) { _, _ in
                sessionDrag = nil
                sessionDropCommitted = false
                reconcileBrowserLocalOrders(sortUpdatedAccounts: true)
            }
            .onAppear {
                reconcileBrowserLocalOrders(sortUpdatedAccounts: true)
            }
            .sheet(item: $workspaceRenameTarget) { target in
                NativeRenameSheet(
                    title: OfficialUISpec.Text.renameWorkspaceTitle,
                    fieldLabel: OfficialUISpec.Text.workspaceName,
                    draft: $renameDraft,
                    conflict: workspaceRenameConflict(target),
                    error: renameError,
                    submitting: renaming,
                    blocked: workspaceRenameBlocked(target),
                    cancel: { closeWorkspaceRename() },
                    confirm: { commitWorkspaceRename(target) }
                )
            }
            .sheet(item: $sessionRenameTarget) { target in
                NativeRenameSheet(
                    title: OfficialUISpec.Text.renameSessionTitle,
                    fieldLabel: OfficialUISpec.Text.sessionName,
                    draft: $renameDraft,
                    conflict: nil,
                    error: renameError,
                    submitting: renaming,
                    blocked: sessionRenameBlocked,
                    cancel: { closeSessionRename() },
                    confirm: { commitSessionRename(target) }
                )
            }
            .sheet(item: $deleteTarget) { target in
                NativeWorkspaceDeleteSheet(
                    description: OfficialUISpec.Text.deleteWorkspaceDescription(name: target.title),
                    submitting: deleting,
                    error: deleteError,
                    cancel: { closeDelete() },
                    confirm: { commitWorkspaceDelete(target) }
                )
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: OfficialUISpec.Spacing.p4) {
            if !searchExpanded {
                Text(OfficialUISpec.Text.workspaces)
                    .font(OfficialUISpec.Typography.s14)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            searchControl

            if !searchExpanded {
                Menu {
                    Text(OfficialUISpec.Text.groupBy)
                    Button(OfficialUISpec.Text.groupByWorkspace) {
                        sessionGroupMode = .workspace
                    }
                    .disabled(sessionGroupMode == .workspace)
                    Button(OfficialUISpec.Text.groupByFlat) {
                        sessionGroupMode = .flat
                    }
                    .disabled(sessionGroupMode == .flat)
                    Divider()
                    Text(OfficialUISpec.Text.orderBy)
                    Divider()
                    Button(OfficialUISpec.Text.orderByManual) {
                        sessionOrderMode = .manual
                    }
                    .disabled(sessionOrderMode == .manual)
                    Button(OfficialUISpec.Text.orderByUpdated) {
                        sessionOrderMode = .updated
                    }
                    .disabled(sessionOrderMode == .updated)
                } label: {
                    OfficialAssetImage(name: "icon-personalization", template: true)
                        .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                        .frame(
                            width: OfficialUISpec.Layout.workspaceIconControl,
                            height: OfficialUISpec.Layout.workspaceIconControl
                        )
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(OfficialUISpec.Text.viewOptions)

                Button(action: actions.addWorkspace) {
                    OfficialAssetImage(name: "icon-project-add", template: true)
                        .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                        .frame(
                            width: OfficialUISpec.Layout.workspaceIconControl,
                            height: OfficialUISpec.Layout.workspaceIconControl
                        )
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.addWorkspace)
            }
        }
        .frame(height: OfficialUISpec.Layout.workspaceSectionHeaderHeight)
        .padding(.leading, OfficialUISpec.Spacing.p4)
        .padding(.bottom, OfficialUISpec.Spacing.p4)
    }

    private var searchControl: some View {
        HStack(spacing: OfficialUISpec.Spacing.p0) {
            Button(action: toggleSearch) {
                OfficialAssetImage(name: "icon-search", template: true)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                    .frame(
                        width: OfficialUISpec.Layout.workspaceIconControl,
                        height: searchExpanded
                            ? OfficialUISpec.Layout.workspaceSearchExpandedHeight
                            : OfficialUISpec.Layout.workspaceIconControl
                    )
            }
            .buttonStyle(OfficialCircleIconButtonStyle())
            .accessibilityLabel(OfficialUISpec.Text.searchSessionsAccessibility)

            if searchExpanded {
                TextField(OfficialUISpec.Text.searchSessionsPlaceholder, text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .accessibilityLabel(OfficialUISpec.Text.searchSessionsAccessibility)

                if !store.searchQuery.isEmpty {
                    Button(action: { store.searchQuery = "" }) {
                        OfficialAssetImage(name: "icon-close", template: true)
                            .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                            .frame(width: OfficialUISpec.Geometry.px24, height: OfficialUISpec.Geometry.px24)
                    }
                    .buttonStyle(OfficialCircleIconButtonStyle())
                    .accessibilityLabel(OfficialUISpec.Text.clearSearch)
                }
            }
        }
        .frame(maxWidth: searchExpanded ? .infinity : OfficialUISpec.Layout.workspaceIconControl)
        .frame(height: searchExpanded ? OfficialUISpec.Layout.workspaceSearchExpandedHeight : OfficialUISpec.Layout.workspaceIconControl)
        .overlay {
            RoundedRectangle(cornerRadius: searchExpanded ? 10 : OfficialUISpec.Layout.workspaceIconControl / 2, style: .continuous)
                .stroke(searchExpanded ? OfficialUISpec.Token.border : Color.clear, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: searchExpanded)
    }

    @ViewBuilder
    private var listArea: some View {
        ScrollView {
            LazyVStack(spacing: OfficialUISpec.Layout.workspaceListRowGap) {
                if searchIsActive {
                    searchResults
                } else {
                    workspaceGroups
                }
            }
            .padding(.leading, OfficialUISpec.Spacing.p4)
            .padding(.trailing, OfficialUISpec.Spacing.p2)
            .padding(.bottom, OfficialUISpec.Spacing.p16)
        }
        .accessibilityLabel(searchIsActive
            ? OfficialUISpec.Text.searchSessionsAccessibility
            : OfficialUISpec.Text.sessions)
    }

    @ViewBuilder
    private var workspaceGroups: some View {
        let snapshot = store.snapshot
        let groups = snapshot.workspaces
        if sessionGroupMode == .flat {
            NativeFlatSessionListView(
                sessions: orderedSessions(
                    flatSessions(in: snapshot),
                    accountKey: NativeWorkspaceBrowserOrdering.flatSessionOrderKey
                ),
                selectedSessionID: snapshot.selectedSessionID,
                sessionDragActive: sessionDrag?.accountKey == NativeWorkspaceBrowserOrdering.flatSessionOrderKey,
                sessionMarker: { sessionID in
                    sessionDrag?.over?.id == sessionID ? sessionDrag?.over?.half : nil
                },
                onSelectSession: { sessionID in
                    let workspaceID = snapshot.workspaces.first { $0.sessionIds.contains(sessionID) }?.workspaceId
                    actions.selectSession(sessionID, workspaceID)
                },
                onStartSessionDrag: {
                    startSessionDrag($0, accountKey: NativeWorkspaceBrowserOrdering.flatSessionOrderKey)
                },
                onHoverSessionDrag: { hoverSessionDrag(over: $0, half: $1) },
                onDropSessionDrag: { commitSessionDrag(over: $0, half: $1) },
                onExitSessionDrag: { sessionID in
                    if sessionDrag?.over?.id == sessionID { sessionDrag?.over = nil }
                },
                actions: rowActions
            )
        } else if groups.isEmpty && snapshot.ungroupedSessions.isEmpty {
            NativeWorkspaceEmptyState(text: OfficialUISpec.Text.noSessionsYet)
        } else {
            ForEach(groups) { workspace in
                let sessions = orderedSessions(
                    snapshot.sessions(in: workspace),
                    accountKey: workspace.workspaceId
                )
                NativeWorkspaceGroupView(
                    workspace: workspace,
                    hostHome: hostHome,
                    sessions: sessions,
                    selectedSessionID: snapshot.selectedSessionID,
                    expanded: expandedWorkspaceIDs.contains(workspace.workspaceId),
                    workspaceMarker: workspaceDrag?.over?.id == workspace.workspaceId ? workspaceDrag?.over?.half : nil,
                    workspaceDragActive: workspaceDrag != nil,
                    sessionDragActive: sessionDrag?.accountKey == workspace.workspaceId,
                    sessionMarker: { sessionID in
                        sessionDrag?.over?.id == sessionID ? sessionDrag?.over?.half : nil
                    },
                    onToggle: { toggleWorkspace(workspace.workspaceId) },
                    onCreateSession: { actions.createSession(workspace.workspaceId) },
                    onSelectSession: { actions.selectSession($0, workspace.workspaceId) },
                    onStartWorkspaceDrag: { startWorkspaceDrag(workspace.workspaceId) },
                    onHoverWorkspaceDrag: { hoverWorkspaceDrag(over: workspace.workspaceId, half: $0) },
                    onDropWorkspaceDrag: { commitWorkspaceDrag(over: workspace.workspaceId, half: $0) },
                    onExitWorkspaceDrag: {
                        if workspaceDrag?.over?.id == workspace.workspaceId { workspaceDrag?.over = nil }
                    },
                    onStartSessionDrag: { startSessionDrag($0, accountKey: workspace.workspaceId) },
                    onHoverSessionDrag: { hoverSessionDrag(over: $0, half: $1) },
                    onDropSessionDrag: { commitSessionDrag(over: $0, half: $1) },
                    onExitSessionDrag: { sessionID in
                        if sessionDrag?.over?.id == sessionID { sessionDrag?.over = nil }
                    },
                    actions: rowActions
                )
            }

            if !snapshot.ungroupedSessions.isEmpty {
                NativeUngroupedWorkspaceGroupView(
                    hostHome: hostHome,
                    sessions: orderedSessions(
                        snapshot.ungroupedSessions,
                        accountKey: NativeWorkspaceBrowserOrdering.ungroupedAccountKey
                    ),
                    selectedSessionID: snapshot.selectedSessionID,
                    expanded: expandedWorkspaceIDs.contains(ungroupedWorkspaceKey),
                    sessionDragActive: sessionDrag?.accountKey == NativeWorkspaceBrowserOrdering.ungroupedAccountKey,
                    sessionMarker: { sessionID in
                        sessionDrag?.over?.id == sessionID ? sessionDrag?.over?.half : nil
                    },
                    onToggle: { toggleWorkspace(ungroupedWorkspaceKey) },
                    onSelectSession: { actions.selectSession($0, nil) },
                    onStartSessionDrag: {
                        startSessionDrag($0, accountKey: NativeWorkspaceBrowserOrdering.ungroupedAccountKey)
                    },
                    onHoverSessionDrag: { hoverSessionDrag(over: $0, half: $1) },
                    onDropSessionDrag: { commitSessionDrag(over: $0, half: $1) },
                    onExitSessionDrag: { sessionID in
                        if sessionDrag?.over?.id == sessionID { sessionDrag?.over = nil }
                    },
                    actions: rowActions
                )
            }
        }
    }

    private struct SearchResult: Identifiable {
        let session: SessionSummaryDTO
        let workspaceID: String?
        let workspaceTitle: String
        let snippet: String?

        var id: String { session.sessionId }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = matchingSessions
        ForEach(results) { result in
            nativeSearchResultRow(
                result,
                selected: result.session.sessionId == store.snapshot.selectedSessionID
            )
        }
        if remoteSearchIsPending {
            NativeWorkspaceSearchStatus(text: OfficialUISpec.Text.searchingSessionHistory, warning: false)
        }
        if store.remoteSearch.status == .failed {
            NativeWorkspaceSearchStatus(text: OfficialUISpec.Text.contentSearchUnavailable, warning: true)
        }
        if !remoteSearchIsPending && results.isEmpty {
            NativeWorkspaceEmptyState(text: OfficialUISpec.Text.noMatchingSessions)
        }
        if matchingHasMore {
            NativeWorkspaceSearchStatus(
                text: OfficialUISpec.Text.searchHasMore(OfficialUISpec.Layout.sessionSearchResultLimit),
                warning: false
            )
        }
    }

    private var searchIsActive: Bool {
        !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var remoteSearchIsPending: Bool {
        let query = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && (store.remoteSearch.query != query || store.remoteSearch.status == .loading)
    }

    private var matchingHasMore: Bool {
        let query = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        let currentRemote = store.remoteSearch.query == query ? store.remoteSearch : .idle
        return currentRemote.hasMore || mergedSearchResults.count > OfficialUISpec.Layout.sessionSearchResultLimit
    }

    private var matchingSessions: [SearchResult] {
        Array(mergedSearchResults.prefix(OfficialUISpec.Layout.sessionSearchResultLimit))
    }

    private var mergedSearchResults: [SearchResult] {
        let query = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let snapshot = store.snapshot
        let queryFolded = query.lowercased()
        var workspaceBySession: [String: (id: String, title: String)] = [:]
        for workspace in snapshot.workspaces {
            for sessionID in workspace.sessionIds where workspaceBySession[sessionID] == nil {
                workspaceBySession[sessionID] = (workspace.workspaceId, workspace.title)
            }
        }
        let local = snapshot.visibleSessions.filter { session in
            let workspaceTitle = workspaceBySession[session.sessionId]?.title ?? session.cwd ?? OfficialUISpec.Text.ungrouped
            return sessionTitle(session).lowercased().contains(queryFolded)
                || workspaceTitle.lowercased().contains(queryFolded)
        }.sorted { $0.updatedAt > $1.updatedAt }
        let remote = store.remoteSearch.query == query ? store.remoteSearch.items : []
        let remoteSnippetBySession = Dictionary(remote.map { ($0.sessionId, $0.snippet) }, uniquingKeysWith: { first, _ in first })
        let visibleByID = Dictionary(snapshot.visibleSessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [SessionSummaryDTO] = []
        var included = Set<String>()
        func include(_ session: SessionSummaryDTO) {
            guard included.insert(session.sessionId).inserted else { return }
            ordered.append(session)
        }
        local.forEach(include)
        for item in remote {
            if let session = visibleByID[item.sessionId] { include(session) }
        }
        return ordered.map { session in
            let workspace = workspaceBySession[session.sessionId]
            return SearchResult(
                session: session,
                workspaceID: workspace?.id,
                workspaceTitle: workspace?.title ?? session.cwd ?? OfficialUISpec.Text.ungrouped,
                snippet: remoteSnippetBySession[session.sessionId]
            )
        }
    }

    private func nativeSearchResultRow(_ result: SearchResult, selected: Bool) -> some View {
        Button(action: { actions.selectSession(result.session.sessionId, result.workspaceID) }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: OfficialUISpec.Spacing.p0) {
                    NativeSessionStatusDot(state: NativeSessionVisualState.resolve(result.session))
                        .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px20)
                    Text(sessionTitle(result.session))
                        .font(OfficialUISpec.Typography.s14)
                        .lineLimit(1)
                        .frame(height: OfficialUISpec.Geometry.px20, alignment: .leading)
                        .padding(.leading, OfficialUISpec.Spacing.p4)
                }
                HStack(spacing: OfficialUISpec.Spacing.p6) {
                    Text(result.workspaceTitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    if let snippet = result.snippet {
                        Text(snippet)
                            .lineLimit(1)
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(OfficialUISpec.Typography.xxs12)
                .frame(height: OfficialUISpec.Geometry.px17, alignment: .leading)
                .padding(.leading, OfficialUISpec.Spacing.p20)
            }
            .foregroundStyle(OfficialUISpec.Token.primary)
            .frame(maxWidth: .infinity, minHeight: OfficialUISpec.Geometry.px48, alignment: .leading)
            .padding(.horizontal, OfficialUISpec.Spacing.p8)
            .background(
                selected ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sessionTitle(result.session))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rowActions: Actions {
        var local = actions
        local.renameWorkspace = { workspaceID, title in
            actions.presentWorkspaceRename(workspaceID, title)
        }
        local.deleteWorkspace = { workspaceID, title in
            actions.presentWorkspaceDelete(workspaceID, title)
        }
        local.renameSession = { sessionID, title in
            actions.presentSessionRename(sessionID, title)
        }
        return local
    }

    private func workspaceRenameConflict(_ target: RenameTarget) -> String? {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != target.title, store.snapshot.workspaces.contains(where: { $0.title == trimmed }) else { return nil }
        return OfficialUISpec.Text.workspaceNameConflict(trimmed)
    }

    private func workspaceRenameBlocked(_ target: RenameTarget) -> Bool {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return renaming || trimmed.isEmpty || trimmed == target.title || workspaceRenameConflict(target) != nil
    }

    private var sessionRenameBlocked: Bool {
        renaming || renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func closeWorkspaceRename() {
        guard !renaming else { return }
        workspaceRenameTarget = nil
        renameError = nil
    }

    private func closeSessionRename() {
        guard !renaming else { return }
        sessionRenameTarget = nil
        renameError = nil
    }

    private func closeDelete() {
        guard !deleting else { return }
        deleteTarget = nil
        deleteError = nil
    }

    private func commitWorkspaceRename(_ target: RenameTarget) {
        guard !workspaceRenameBlocked(target) else { return }
        renaming = true
        renameError = nil
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await actions.commitWorkspaceRename(target.id, title)
                renaming = false
                workspaceRenameTarget = nil
            } catch {
                renaming = false
                renameError = error.localizedDescription
            }
        }
    }

    private func commitSessionRename(_ target: RenameTarget) {
        guard !sessionRenameBlocked else { return }
        renaming = true
        renameError = nil
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await actions.commitSessionRename(target.id, title)
                renaming = false
                sessionRenameTarget = nil
            } catch {
                renaming = false
                renameError = error.localizedDescription
            }
        }
    }

    private func commitWorkspaceDelete(_ target: DeleteTarget) {
        guard !deleting else { return }
        deleting = true
        deleteCommittedID = nil
        deleteError = nil
        Task {
            do {
                try await actions.commitWorkspaceDelete(target.id)
                deleteCommittedID = target.id
            } catch {
                deleting = false
                deleteError = error.localizedDescription
            }
        }
    }

    /// Source: RC8 `nextSessionOrderAccount`. Every browser-local account is
    /// reconciled against current Host membership; `updated` then promotes only
    /// newly active sessions while keeping manually edited unaffected order.
    private func reconcileBrowserLocalOrders(sortUpdatedAccounts: Bool = false) {
        let snapshot = store.snapshot
        let sessionByID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.sessionId, $0) })
        let accountedIDs = Set(snapshot.workspaces.flatMap(\.sessionIds))
        var accounts: [(key: String, sessionIDs: [String])] = snapshot.workspaces.map {
            ($0.workspaceId, $0.sessionIds.filter { sessionByID[$0] != nil })
        }
        accounts.append((
            NativeWorkspaceBrowserOrdering.ungroupedAccountKey,
            snapshot.visibleSessions.map(\.sessionId).filter { !accountedIDs.contains($0) }
        ))
        accounts.append((
            NativeWorkspaceBrowserOrdering.flatSessionOrderKey,
            flatSessions(in: snapshot).map(\.sessionId)
        ))

        var nextOrderByAccount: [String: [String]] = [:]
        var nextUpdatedAtByAccount: [String: [String: Double]] = [:]
        for account in accounts {
            let sessions = account.sessionIDs.compactMap { sessionByID[$0] }
            var order = NativeWorkspaceBrowserOrdering.reconciledOrder(
                hostIDs: account.sessionIDs,
                storedOrder: sessionOrderByAccount[account.key]
            )
            if sessionOrderMode == .updated {
                let previousUpdatedAt = sessionUpdatedAtByAccount[account.key] ?? [:]
                let promoted = sessions.filter { session in
                    sortUpdatedAccounts
                        || previousUpdatedAt[session.sessionId] == nil
                        || session.updatedAt > (previousUpdatedAt[session.sessionId] ?? -.infinity)
                }.sorted { lhs, rhs in
                    lhs.updatedAt == rhs.updatedAt
                        ? lhs.sessionId < rhs.sessionId
                        : lhs.updatedAt > rhs.updatedAt
                }
                if !promoted.isEmpty {
                    let promotedIDs = Set(promoted.map(\.sessionId))
                    order = promoted.map(\.sessionId) + order.filter { !promotedIDs.contains($0) }
                }
            }
            nextOrderByAccount[account.key] = order
            nextUpdatedAtByAccount[account.key] = Dictionary(
                uniqueKeysWithValues: sessions.map { ($0.sessionId, $0.updatedAt) }
            )
        }
        sessionOrderByAccount = nextOrderByAccount
        sessionUpdatedAtByAccount = nextUpdatedAtByAccount
    }

    /// Source: RC8 `deriveFlat`: every browser-visible session is a top-level
    /// row, newest first with stable session identity tie-break before local
    /// flat-account reconciliation is applied.
    private func flatSessions(in snapshot: NativeWorkspaceStore.Snapshot) -> [SessionSummaryDTO] {
        snapshot.visibleSessions.sorted { lhs, rhs in
            lhs.updatedAt == rhs.updatedAt
                ? lhs.sessionId < rhs.sessionId
                : lhs.updatedAt > rhs.updatedAt
        }
    }

    private func orderedSessions(_ sessions: [SessionSummaryDTO], accountKey: String) -> [SessionSummaryDTO] {
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
        let order = NativeWorkspaceBrowserOrdering.reconciledOrder(
            hostIDs: sessions.map(\.sessionId),
            storedOrder: sessionOrderByAccount[accountKey]
        )
        return order.compactMap { sessionByID[$0] }
    }

    private func startWorkspaceDrag(_ workspaceID: String) {
        workspaceDropCommitted = false
        workspaceDrag = WorkspaceDrag(workspaceID: workspaceID, over: nil)
    }

    private func hoverWorkspaceDrag(over workspaceID: String, half: NativeWorkspaceBrowserOrdering.DropHalf) {
        guard workspaceDrag != nil else { return }
        workspaceDrag?.over = DropTarget(id: workspaceID, half: half)
    }

    @discardableResult
    private func commitWorkspaceDrag(over workspaceID: String, half: NativeWorkspaceBrowserOrdering.DropHalf) -> Bool {
        guard !workspaceDropCommitted, let active = workspaceDrag else { return false }
        workspaceDropCommitted = true
        workspaceDrag = nil
        let decision = NativeWorkspaceBrowserOrdering.workspaceDecision(
            workspaceID: active.workspaceID,
            overWorkspaceID: workspaceID,
            half: half,
            workspaceIDs: store.snapshot.workspaces.map(\.workspaceId)
        )
        guard case let .host(workspaceID, beforeWorkspaceID) = decision else { return true }
        Task {
            do {
                try await actions.moveWorkspace(workspaceID, beforeWorkspaceID)
            } catch {
                // RC8 retains the Host-authoritative order on rejection; a
                // later Host frame/refresh remains the only visual authority.
            }
        }
        return true
    }

    private func startSessionDrag(_ sessionID: String, accountKey: String) {
        sessionDropCommitted = false
        sessionDrag = SessionDrag(accountKey: accountKey, sessionID: sessionID, over: nil)
    }

    private func hoverSessionDrag(over sessionID: String, half: NativeWorkspaceBrowserOrdering.DropHalf) {
        guard sessionDrag != nil else { return }
        sessionDrag?.over = DropTarget(id: sessionID, half: half)
    }

    @discardableResult
    private func commitSessionDrag(over sessionID: String, half: NativeWorkspaceBrowserOrdering.DropHalf) -> Bool {
        guard !sessionDropCommitted, let active = sessionDrag else { return false }
        sessionDropCommitted = true
        sessionDrag = nil
        let snapshot = store.snapshot
        let hostOrder: [String]
        if active.accountKey == NativeWorkspaceBrowserOrdering.ungroupedAccountKey {
            hostOrder = snapshot.ungroupedSessions.map(\.sessionId)
        } else if active.accountKey == NativeWorkspaceBrowserOrdering.flatSessionOrderKey {
            hostOrder = flatSessions(in: snapshot).map(\.sessionId)
        } else {
            hostOrder = snapshot.workspaces.first(where: { $0.workspaceId == active.accountKey })?.sessionIds ?? []
        }
        let ordered = NativeWorkspaceBrowserOrdering.reconciledOrder(
            hostIDs: hostOrder,
            storedOrder: sessionOrderByAccount[active.accountKey]
        )
        let decision = NativeWorkspaceBrowserOrdering.sessionDecision(
            sessionID: active.sessionID,
            accountKey: active.accountKey,
            overSessionID: sessionID,
            half: half,
            orderedSessionIDs: ordered,
            orderMode: sessionOrderMode
        )
        switch decision {
        case .noOp:
            return true
        case let .local(order):
            sessionOrderByAccount[active.accountKey] = order
        case let .host(sessionID, workspaceID, beforeSessionID, viewOrder):
            sessionOrderByAccount[active.accountKey] = viewOrder
            Task {
                do {
                    try await actions.moveSession(sessionID, workspaceID, beforeSessionID)
                } catch {
                    // A rejected manual reorder must not invent durable order;
                    // the next Host refresh reconciles this local account.
                }
            }
        }
        return true
    }

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.18)) {
            searchExpanded.toggle()
        }
        if !searchExpanded { store.searchQuery = "" }
    }

    private func toggleWorkspace(_ workspaceID: String) {
        if expandedWorkspaceIDs.contains(workspaceID) {
            expandedWorkspaceIDs.remove(workspaceID)
        } else {
            expandedWorkspaceIDs.insert(workspaceID)
        }
    }
}

private let ungroupedWorkspaceKey = ""

private struct NativeWorkspaceSearchStatus: View {
    let text: String
    let warning: Bool

    var body: some View {
        Text(text)
            .font(OfficialUISpec.Typography.xxs12)
            .foregroundStyle(warning ? OfficialUISpec.Token.warningPrimary : OfficialUISpec.Token.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OfficialUISpec.Spacing.p8)
            .padding(.vertical, OfficialUISpec.Spacing.p4)
    }
}

private struct NativeRenameSheet: View {
    let title: String
    let fieldLabel: String
    @Binding var draft: String
    let conflict: String?
    let error: String?
    let submitting: Bool
    let blocked: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(OfficialUISpec.Typography.baseStrong16)
                .foregroundStyle(OfficialUISpec.Token.primary)
            TextField(fieldLabel, text: $draft)
                .textFieldStyle(.roundedBorder)
                .disabled(submitting)
                .focused($focused)
                .onSubmit(confirm)
            if let conflict {
                Text(conflict)
                    .font(OfficialUISpec.Typography.xxs12)
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
            }
            if let error {
                Text(error)
                    .font(OfficialUISpec.Typography.xxs12)
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
            }
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Spacer(minLength: 0)
                Button(OfficialUISpec.Text.cancel, action: cancel)
                    .disabled(submitting)
                Button(OfficialUISpec.Text.rename, action: confirm)
                    .disabled(blocked)
            }
        }
        .padding(OfficialUISpec.Spacing.p20)
        .frame(width: OfficialUISpec.Geometry.px360)
        .onAppear { focused = true }
    }
}

private struct NativeWorkspaceDeleteSheet: View {
    let description: String
    let submitting: Bool
    let error: String?
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(OfficialUISpec.Text.deleteWorkspace)
                .font(OfficialUISpec.Typography.baseStrong16)
                .foregroundStyle(OfficialUISpec.Token.primary)
            Text(description)
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if submitting {
                Text(OfficialUISpec.Text.deletingWorkspace)
                    .font(OfficialUISpec.Typography.xxs12)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
            if let error {
                Text(error)
                    .font(OfficialUISpec.Typography.xxs12)
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
            }
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Spacer(minLength: 0)
                Button(OfficialUISpec.Text.cancel, action: cancel)
                    .disabled(submitting)
                Button(OfficialUISpec.Text.deleteWorkspace, action: confirm)
                    .disabled(submitting)
            }
        }
        .padding(OfficialUISpec.Spacing.p20)
        .frame(width: OfficialUISpec.Geometry.px400)
    }
}

private struct WorkspaceBrowserRail: View {
    let requestSidebarExpansion: () -> Void
    let addWorkspace: () -> Void

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p12) {
            Button(action: requestSidebarExpansion) {
                OfficialAssetImage(name: "icon-search", template: true)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                    .frame(
                        width: OfficialUISpec.Layout.workspaceRailControl,
                        height: OfficialUISpec.Layout.workspaceRailControl
                    )
            }
            .buttonStyle(OfficialCircleIconButtonStyle(pressedForeground: OfficialUISpec.Token.primary))
            .accessibilityLabel(OfficialUISpec.Text.searchSessionsAccessibility)

            Button(action: addWorkspace) {
                OfficialAssetImage(name: "icon-project-add", template: true)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                    .frame(
                        width: OfficialUISpec.Layout.workspaceRailControl,
                        height: OfficialUISpec.Layout.workspaceRailControl
                    )
            }
            .buttonStyle(OfficialCircleIconButtonStyle(pressedForeground: OfficialUISpec.Token.primary))
            .accessibilityLabel(OfficialUISpec.Text.addWorkspace)
            Spacer(minLength: 0)
        }
        .padding(.top, OfficialUISpec.Spacing.p12)
    }
}

private struct NativeWorkspaceGroupView: View {
    let workspace: WorkspaceSummaryDTO
    let hostHome: String?
    let sessions: [SessionSummaryDTO]
    let selectedSessionID: String?
    let expanded: Bool
    let workspaceMarker: NativeWorkspaceBrowserOrdering.DropHalf?
    let workspaceDragActive: Bool
    let sessionDragActive: Bool
    let sessionMarker: (String) -> NativeWorkspaceBrowserOrdering.DropHalf?
    let onToggle: () -> Void
    let onCreateSession: () -> Void
    let onSelectSession: (String) -> Void
    let onStartWorkspaceDrag: () -> Void
    let onHoverWorkspaceDrag: (NativeWorkspaceBrowserOrdering.DropHalf) -> Void
    let onDropWorkspaceDrag: (NativeWorkspaceBrowserOrdering.DropHalf) -> Bool
    let onExitWorkspaceDrag: () -> Void
    let onStartSessionDrag: (String) -> Void
    let onHoverSessionDrag: (String, NativeWorkspaceBrowserOrdering.DropHalf) -> Void
    let onDropSessionDrag: (String, NativeWorkspaceBrowserOrdering.DropHalf) -> Bool
    let onExitSessionDrag: (String) -> Void
    let actions: WorkspaceBrowserView.Actions

    var body: some View {
        VStack(spacing: OfficialUISpec.Layout.workspaceListRowGap) {
            NativeWorkspaceRow(
                title: workspace.title,
                path: workspace.path,
                home: hostHome,
                expanded: expanded,
                onToggle: onToggle,
                onCreateSession: onCreateSession,
                onStartDrag: onStartWorkspaceDrag,
                actions: actions,
                workspaceID: workspace.workspaceId
            )

            if expanded {
                ForEach(sessions.prefix(OfficialUISpec.Layout.workspaceGroupSessionLimit)) { session in
                    NativeSessionRow(
                        session: session,
                        selected: session.sessionId == selectedSessionID,
                        marker: sessionMarker(session.sessionId),
                        dragActive: sessionDragActive,
                        onSelect: { onSelectSession(session.sessionId) },
                        onStartDrag: { onStartSessionDrag(session.sessionId) },
                        onHoverDrag: { onHoverSessionDrag(session.sessionId, $0) },
                        onDropDrag: { onDropSessionDrag(session.sessionId, $0) },
                        onExitDrag: { onExitSessionDrag(session.sessionId) },
                        actions: actions
                    )
                }
            }
        }
        .nativeWorkspaceDropTarget(
            active: { workspaceDragActive },
            hover: onHoverWorkspaceDrag,
            drop: onDropWorkspaceDrag,
            exited: onExitWorkspaceDrag
        )
        .overlay(alignment: workspaceMarker == .after ? .bottom : .top) {
            if let workspaceMarker {
                NativeWorkspaceDropMarker(half: workspaceMarker)
            }
        }
    }
}

/// Source: RC8 `FlatList`: every visible session is a top-level browser row.
/// Its `__flat_session_order__` account is always local, including manual mode.
private struct NativeFlatSessionListView: View {
    let sessions: [SessionSummaryDTO]
    let selectedSessionID: String?
    let sessionDragActive: Bool
    let sessionMarker: (String) -> NativeWorkspaceBrowserOrdering.DropHalf?
    let onSelectSession: (String) -> Void
    let onStartSessionDrag: (String) -> Void
    let onHoverSessionDrag: (String, NativeWorkspaceBrowserOrdering.DropHalf) -> Void
    let onDropSessionDrag: (String, NativeWorkspaceBrowserOrdering.DropHalf) -> Bool
    let onExitSessionDrag: (String) -> Void
    let actions: WorkspaceBrowserView.Actions

    var body: some View {
        if sessions.isEmpty {
            NativeWorkspaceEmptyState(text: OfficialUISpec.Text.noSessionsYet)
        } else {
            ForEach(sessions) { session in
                NativeSessionRow(
                    session: session,
                    selected: session.sessionId == selectedSessionID,
                    marker: sessionMarker(session.sessionId),
                    dragActive: sessionDragActive,
                    onSelect: { onSelectSession(session.sessionId) },
                    onStartDrag: { onStartSessionDrag(session.sessionId) },
                    onHoverDrag: { onHoverSessionDrag(session.sessionId, $0) },
                    onDropDrag: { onDropSessionDrag(session.sessionId, $0) },
                    onExitDrag: { onExitSessionDrag(session.sessionId) },
                    actions: actions
                )
            }
        }
    }
}

private struct NativeUngroupedWorkspaceGroupView: View {
    let hostHome: String?
    let sessions: [SessionSummaryDTO]
    let selectedSessionID: String?
    let expanded: Bool
    let sessionDragActive: Bool
    let sessionMarker: (String) -> NativeWorkspaceBrowserOrdering.DropHalf?
    let onToggle: () -> Void
    let onSelectSession: (String) -> Void
    let onStartSessionDrag: (String) -> Void
    let onHoverSessionDrag: (String, NativeWorkspaceBrowserOrdering.DropHalf) -> Void
    let onDropSessionDrag: (String, NativeWorkspaceBrowserOrdering.DropHalf) -> Bool
    let onExitSessionDrag: (String) -> Void
    let actions: WorkspaceBrowserView.Actions

    var body: some View {
        VStack(spacing: OfficialUISpec.Layout.workspaceListRowGap) {
            NativeWorkspaceRow(
                title: OfficialUISpec.Text.ungrouped,
                path: nil,
                home: hostHome,
                expanded: expanded,
                onToggle: onToggle,
                onCreateSession: {},
                onStartDrag: nil,
                actions: actions,
                workspaceID: nil
            )
            if expanded {
                ForEach(sessions.prefix(OfficialUISpec.Layout.workspaceGroupSessionLimit)) { session in
                    NativeSessionRow(
                        session: session,
                        selected: session.sessionId == selectedSessionID,
                        marker: sessionMarker(session.sessionId),
                        dragActive: sessionDragActive,
                        onSelect: { onSelectSession(session.sessionId) },
                        onStartDrag: { onStartSessionDrag(session.sessionId) },
                        onHoverDrag: { onHoverSessionDrag(session.sessionId, $0) },
                        onDropDrag: { onDropSessionDrag(session.sessionId, $0) },
                        onExitDrag: { onExitSessionDrag(session.sessionId) },
                        actions: actions
                    )
                }
            }
        }
    }
}

private struct NativeWorkspaceRow: View {
    let title: String
    /// The full Host path stays authoritative; only hover display is abbreviated.
    let path: String?
    let home: String?
    let expanded: Bool
    let onToggle: () -> Void
    let onCreateSession: () -> Void
    /// Nil for the synthetic ungrouped group, which RC8 never permits as a
    /// workspace drag source.
    let onStartDrag: (() -> Void)?
    let actions: WorkspaceBrowserView.Actions
    let workspaceID: String?

    private var hoverPath: String? {
        path.map { HostPathDisplay.abbreviateHomePath($0, home: home) }
    }

    var body: some View {
        let row = HStack(spacing: OfficialUISpec.Spacing.p6) {
            Button(action: onToggle) {
                OfficialAssetImage(name: expanded ? "icon-folder-open" : "icon-folder-close", template: true)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)

            Text(title)
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .lineLimit(1)
            Spacer(minLength: 0)

            if let workspaceID {
                Menu {
                    Button(OfficialUISpec.Text.rename) { actions.renameWorkspace(workspaceID, title) }
                    Button(OfficialUISpec.Text.deleteWorkspace) { actions.deleteWorkspace(workspaceID, title) }
                } label: {
                    OfficialAssetImage(name: "icon-ellipsis", template: true)
                        .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                        .frame(width: OfficialUISpec.Geometry.px20, height: OfficialUISpec.Geometry.px20)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(OfficialUISpec.Text.workspaceActionsAccessibilityPrefix + title)
            }

            Button(action: onCreateSession) {
                OfficialAssetImage(name: "icon-plus", template: true)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                    .frame(width: OfficialUISpec.Geometry.px20, height: OfficialUISpec.Geometry.px20)
            }
            .buttonStyle(OfficialCircleIconButtonStyle())
        }
        .frame(height: OfficialUISpec.Geometry.px34)
        .padding(.horizontal, OfficialUISpec.Spacing.p8)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .help(hoverPath ?? "")

        if let onStartDrag, let workspaceID {
            row.onDrag {
                onStartDrag()
                return NSItemProvider(object: workspaceID as NSString)
            }
        } else {
            row
        }
    }
}

private struct NativeSessionRow: View {
    let session: SessionSummaryDTO
    let selected: Bool
    let marker: NativeWorkspaceBrowserOrdering.DropHalf?
    let dragActive: Bool
    let onSelect: () -> Void
    let onStartDrag: () -> Void
    let onHoverDrag: (NativeWorkspaceBrowserOrdering.DropHalf) -> Void
    let onDropDrag: (NativeWorkspaceBrowserOrdering.DropHalf) -> Bool
    let onExitDrag: () -> Void
    let actions: WorkspaceBrowserView.Actions
    @State private var isHovering = false

    private var status: NativeSessionVisualState {
        NativeSessionVisualState.resolve(session)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: OfficialUISpec.Spacing.p0) {
                NativeSessionStatusDot(state: status)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px20)
                Text(sessionTitle(session))
                    .font(OfficialUISpec.Typography.s14)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, OfficialUISpec.Spacing.p4)
                    .padding(.trailing, OfficialUISpec.Spacing.p6)
                if !session.blank {
                    if isHovering {
                        Menu {
                            Button(OfficialUISpec.Text.rename) { actions.renameSession(session.sessionId, sessionTitle(session)) }
                            Button(OfficialUISpec.Text.forkSession) { actions.forkSession(session.sessionId) }
                            Button(OfficialUISpec.Text.archiveSession) { actions.archiveSession(session.sessionId) }
                        } label: {
                            OfficialAssetImage(name: "icon-ellipsis", template: true)
                                .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                                .frame(width: OfficialUISpec.Geometry.px20, height: OfficialUISpec.Geometry.px20)
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel(OfficialUISpec.Text.sessionActionsAccessibilityPrefix + sessionTitle(session))
                    } else {
                        Text(NativeRelativeTime.label(updatedAt: session.updatedAt))
                            .font(OfficialUISpec.Typography.xxs12)
                            .foregroundStyle(OfficialUISpec.Token.caption)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .foregroundStyle(OfficialUISpec.Token.primary)
            .frame(height: OfficialUISpec.Geometry.px32)
            .padding(.horizontal, OfficialUISpec.Spacing.p8)
            .background(
                selected ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            onStartDrag()
            return NSItemProvider(object: session.sessionId as NSString)
        }
        .nativeWorkspaceDropTarget(
            active: { dragActive },
            hover: onHoverDrag,
            drop: onDropDrag,
            exited: onExitDrag
        )
        .overlay(alignment: marker == .after ? .bottom : .top) {
            if let marker {
                NativeWorkspaceDropMarker(half: marker)
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel(sessionTitle(session))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Source: RC8 `WorkspaceBrowser.module.css:381-427`. The official marker
/// combines a 2px business-primary insertion line with two 5×7 chevrons.
private struct NativeWorkspaceDropMarker: View {
    let half: NativeWorkspaceBrowserOrdering.DropHalf

    var body: some View {
        Canvas { context, size in
            let color = OfficialUISpec.Token.businessBlue
            let centerY: CGFloat = 5
            var line = Path()
            line.move(to: CGPoint(x: 4, y: centerY))
            line.addLine(to: CGPoint(x: size.width, y: centerY))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2))

            var upperChevron = Path()
            upperChevron.move(to: CGPoint(x: 0, y: 0))
            upperChevron.addLine(to: CGPoint(x: 4, y: 5))
            upperChevron.addLine(to: CGPoint(x: 0, y: 7))
            context.stroke(upperChevron, with: .color(color), style: StrokeStyle(lineWidth: 2))

            var lowerChevron = Path()
            lowerChevron.move(to: CGPoint(x: 0, y: 5))
            lowerChevron.addLine(to: CGPoint(x: 4, y: 10))
            lowerChevron.addLine(to: CGPoint(x: 0, y: 12))
            context.stroke(lowerChevron, with: .color(color), style: StrokeStyle(lineWidth: 2))
        }
        .frame(maxWidth: .infinity)
        .frame(height: OfficialUISpec.Spacing.p12)
        .offset(y: half == .before ? -OfficialUISpec.Spacing.p8 : OfficialUISpec.Spacing.p8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum NativeSessionVisualState {
    case idle
    case warning(String)
    case ongoing

    static func resolve(_ session: SessionSummaryDTO) -> Self {
        switch session.pendingInteraction {
        case "approval":
            return .warning(OfficialUISpec.Text.waitingForApproval)
        case "plan-review":
            return .warning(OfficialUISpec.Text.planAwaitingReview)
        case "question":
            return .warning(OfficialUISpec.Text.waitingForAnswer)
        default:
            return session.running ? .ongoing : .idle
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle:
            return OfficialUISpec.Text.idle
        case .warning(let label):
            return label
        case .ongoing:
            return OfficialUISpec.Text.running
        }
    }
}

private struct NativeSessionStatusDot: View {
    let state: NativeSessionVisualState
    private let matrixCells: [(CGFloat, CGFloat)] = [
        (0, 0), (4, 0), (8, 0), (8, 4), (8, 8), (4, 8), (0, 8), (0, 4),
    ]

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle:
            Color.clear.frame(width: OfficialUISpec.Geometry.px0, height: OfficialUISpec.Geometry.px0)
        case .warning:
            ZStack {
                Circle().fill(OfficialUISpec.Token.warningPrimary.opacity(0.1))
                    .frame(width: OfficialUISpec.Geometry.px10, height: OfficialUISpec.Geometry.px10)
                Circle().fill(OfficialUISpec.Token.warningPrimary)
                    .frame(width: OfficialUISpec.Geometry.px6, height: OfficialUISpec.Geometry.px6)
            }
            .frame(width: OfficialUISpec.Geometry.px10, height: OfficialUISpec.Geometry.px10)
            .accessibilityLabel(state.accessibilityLabel)
        case .ongoing:
            ZStack(alignment: .topLeading) {
                ForEach(Array(matrixCells.enumerated()), id: \.offset) { index, point in
                    Rectangle()
                        .fill(OfficialUISpec.Token.businessBlue.opacity(index == 0 ? 1 : index < 4 ? 0.6 : index < 6 ? 0.35 : 0.15))
                        .frame(width: OfficialUISpec.Geometry.px2, height: OfficialUISpec.Geometry.px2)
                        .offset(x: point.0, y: point.1)
                }
            }
            .frame(width: OfficialUISpec.Geometry.px10, height: OfficialUISpec.Geometry.px10)
            .accessibilityLabel(state.accessibilityLabel)
        }
    }
}

private enum NativeRelativeTime {
    static func label(updatedAt: Double, now: Date = Date()) -> String {
        let difference = max(0, now.timeIntervalSince1970 * 1_000 - updatedAt)
        let minute = 60_000.0
        let hour = 3_600_000.0
        let day = 86_400_000.0
        if difference < minute { return OfficialUISpec.Text.relativeTimeNow }
        if difference < hour {
            return OfficialUISpec.Text.relativeTime(OfficialUISpec.Text.relativeTimeMinutesTemplate, value: Int(floor(difference / minute)))
        }
        if difference < day {
            return OfficialUISpec.Text.relativeTime(OfficialUISpec.Text.relativeTimeHoursTemplate, value: Int(floor(difference / hour)))
        }
        if difference < 30 * day {
            return OfficialUISpec.Text.relativeTime(OfficialUISpec.Text.relativeTimeDaysTemplate, value: Int(floor(difference / day)))
        }
        if difference < 365 * day {
            return OfficialUISpec.Text.relativeTime(OfficialUISpec.Text.relativeTimeMonthsTemplate, value: Int(floor(difference / (30 * day))))
        }
        return OfficialUISpec.Text.relativeTime(OfficialUISpec.Text.relativeTimeYearsTemplate, value: Int(floor(difference / (365 * day))))
    }
}

private struct NativeWorkspaceEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OfficialUISpec.Typography.xxs12)
            .foregroundStyle(OfficialUISpec.Token.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, OfficialUISpec.Spacing.p8)
            .padding(.leading, OfficialUISpec.Spacing.p4)
    }
}

private func sessionTitle(_ session: SessionSummaryDTO) -> String {
    session.blank ? OfficialUISpec.Text.newSession : session.displayTitle ?? OfficialUISpec.Text.newSession
}
