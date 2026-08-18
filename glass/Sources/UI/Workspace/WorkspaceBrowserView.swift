import SwiftUI

/// Native rendering of the official `WorkspaceBrowser` hierarchy. Host state is
/// injected from `NativeWorkspaceStore`; this view holds only browser-local
/// expansion and search-input animation state.
struct WorkspaceBrowserView: View {
    @ObservedObject var store: NativeWorkspaceStore
    let collapsed: Bool
    let requestSidebarExpansion: () -> Void
    let actions: Actions

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
        var commitWorkspaceRename: (String, String) async throws -> Void = { _, _ in }
        var commitWorkspaceDelete: (String) async throws -> Void = { _ in }
        var commitSessionRename: (String, String) async throws -> Void = { _, _ in }
    }

    private struct RenameTarget: Identifiable {
        let id: String
        let title: String
    }

    private struct DeleteTarget: Identifiable {
        let id: String
        let title: String
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

    init(
        store: NativeWorkspaceStore,
        collapsed: Bool,
        requestSidebarExpansion: @escaping () -> Void,
        actions: Actions
    ) {
        self.store = store
        self.collapsed = collapsed
        self.requestSidebarExpansion = requestSidebarExpansion
        self.actions = actions
        _expandedWorkspaceIDs = State(initialValue: Set(store.snapshot.selectedWorkspaceID.map { [$0] } ?? []))
    }

    var body: some View {
        if collapsed {
            WorkspaceBrowserRail(
                requestSidebarExpansion: requestSidebarExpansion,
                addWorkspace: actions.addWorkspace
            )
        } else {
            VStack(spacing: 0) {
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
            .sheet(item: $workspaceRenameTarget) { target in
                NativeRenameSheet(
                    title: OfficialUISpec.Text.renameWorkspaceTitle,
                    fieldLabel: OfficialUISpec.Text.workspaceName,
                    draft: $renameDraft,
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
        HStack(spacing: 4) {
            if !searchExpanded {
                Text(OfficialUISpec.Text.workspaces)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            searchControl

            if !searchExpanded {
                Button(action: {}) {
                    OfficialAssetImage(name: "icon-personalization", template: true)
                        .frame(width: 16, height: 16)
                        .frame(
                            width: OfficialUISpec.Layout.workspaceIconControl,
                            height: OfficialUISpec.Layout.workspaceIconControl
                        )
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.viewOptions)

                Button(action: actions.addWorkspace) {
                    OfficialAssetImage(name: "icon-project-add", template: true)
                        .frame(width: 16, height: 16)
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
        .padding(.leading, 4)
        .padding(.bottom, 4)
    }

    private var searchControl: some View {
        HStack(spacing: 0) {
            Button(action: toggleSearch) {
                OfficialAssetImage(name: "icon-search", template: true)
                    .frame(width: 16, height: 16)
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
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .accessibilityLabel(OfficialUISpec.Text.searchSessionsAccessibility)

                if !store.searchQuery.isEmpty {
                    Button(action: { store.searchQuery = "" }) {
                        OfficialAssetImage(name: "icon-close", template: true)
                            .frame(width: 12, height: 12)
                            .frame(width: 24, height: 24)
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
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .padding(.bottom, 16)
        }
        .accessibilityLabel(searchIsActive
            ? OfficialUISpec.Text.searchSessionsAccessibility
            : OfficialUISpec.Text.sessions)
    }

    @ViewBuilder
    private var workspaceGroups: some View {
        let snapshot = store.snapshot
        let groups = snapshot.workspaces
        if groups.isEmpty && snapshot.ungroupedSessions.isEmpty {
            NativeWorkspaceEmptyState(text: OfficialUISpec.Text.noSessionsYet)
        } else {
            ForEach(groups) { workspace in
                let sessions = snapshot.sessions(in: workspace)
                NativeWorkspaceGroupView(
                    workspace: workspace,
                    sessions: sessions,
                    selectedSessionID: snapshot.selectedSessionID,
                    expanded: expandedWorkspaceIDs.contains(workspace.workspaceId),
                    onToggle: { toggleWorkspace(workspace.workspaceId) },
                    onCreateSession: { actions.createSession(workspace.workspaceId) },
                    onSelectSession: { actions.selectSession($0, workspace.workspaceId) },
                    actions: rowActions
                )
            }

            if !snapshot.ungroupedSessions.isEmpty {
                NativeUngroupedWorkspaceGroupView(
                    sessions: snapshot.ungroupedSessions,
                    selectedSessionID: snapshot.selectedSessionID,
                    expanded: expandedWorkspaceIDs.contains(ungroupedWorkspaceKey),
                    onToggle: { toggleWorkspace(ungroupedWorkspaceKey) },
                    onSelectSession: { actions.selectSession($0, nil) },
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
                HStack(spacing: 0) {
                    NativeSessionStatusDot(state: NativeSessionVisualState.resolve(result.session))
                        .frame(width: 16, height: 20)
                    Text(sessionTitle(result.session))
                        .font(.system(size: 14, weight: .regular))
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
                HStack(spacing: 6) {
                    Text(result.workspaceTitle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let snippet = result.snippet {
                        Text(snippet)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.caption)
                .padding(.leading, 20)
            }
            .foregroundStyle(OfficialUISpec.Token.primary)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                selected ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sessionTitle(result.session))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rowActions: Actions {
        var local = actions
        local.renameWorkspace = { workspaceID, title in
            workspaceRenameTarget = RenameTarget(id: workspaceID, title: title)
            renameDraft = title
            renameError = nil
        }
        local.deleteWorkspace = { workspaceID, title in
            deleteTarget = DeleteTarget(id: workspaceID, title: title)
            deleteError = nil
        }
        local.renameSession = { sessionID, title in
            sessionRenameTarget = RenameTarget(id: sessionID, title: title)
            renameDraft = title
            renameError = nil
        }
        return local
    }

    private func workspaceRenameBlocked(_ target: RenameTarget) -> Bool {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = trimmed != target.title && store.snapshot.workspaces.contains { $0.title == trimmed }
        return renaming || trimmed.isEmpty || trimmed == target.title || duplicate
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
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(warning ? OfficialUISpec.Token.warningPrimary : OfficialUISpec.Token.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

private struct NativeRenameSheet: View {
    let title: String
    let fieldLabel: String
    @Binding var draft: String
    let error: String?
    let submitting: Bool
    let blocked: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(OfficialUISpec.Token.primary)
            TextField(fieldLabel, text: $draft)
                .textFieldStyle(.roundedBorder)
                .disabled(submitting)
                .focused($focused)
                .onSubmit(confirm)
            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(OfficialUISpec.Text.cancel, action: cancel)
                    .disabled(submitting)
                Button(OfficialUISpec.Text.rename, action: confirm)
                    .disabled(blocked)
            }
        }
        .padding(20)
        .frame(width: 360)
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(OfficialUISpec.Token.primary)
            Text(description)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if submitting {
                Text(OfficialUISpec.Text.deletingWorkspace)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(OfficialUISpec.Text.cancel, action: cancel)
                    .disabled(submitting)
                Button(OfficialUISpec.Text.deleteWorkspace, action: confirm)
                    .disabled(submitting)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

private struct WorkspaceBrowserRail: View {
    let requestSidebarExpansion: () -> Void
    let addWorkspace: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: requestSidebarExpansion) {
                OfficialAssetImage(name: "icon-search", template: true)
                    .frame(width: 16, height: 16)
                    .frame(
                        width: OfficialUISpec.Layout.workspaceRailControl,
                        height: OfficialUISpec.Layout.workspaceRailControl
                    )
            }
            .buttonStyle(OfficialCircleIconButtonStyle(pressedForeground: OfficialUISpec.Token.primary))
            .accessibilityLabel(OfficialUISpec.Text.searchSessionsAccessibility)

            Button(action: addWorkspace) {
                OfficialAssetImage(name: "icon-project-add", template: true)
                    .frame(width: 16, height: 16)
                    .frame(
                        width: OfficialUISpec.Layout.workspaceRailControl,
                        height: OfficialUISpec.Layout.workspaceRailControl
                    )
            }
            .buttonStyle(OfficialCircleIconButtonStyle(pressedForeground: OfficialUISpec.Token.primary))
            .accessibilityLabel(OfficialUISpec.Text.addWorkspace)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }
}

private struct NativeWorkspaceGroupView: View {
    let workspace: WorkspaceSummaryDTO
    let sessions: [SessionSummaryDTO]
    let selectedSessionID: String?
    let expanded: Bool
    let onToggle: () -> Void
    let onCreateSession: () -> Void
    let onSelectSession: (String) -> Void
    let actions: WorkspaceBrowserView.Actions

    var body: some View {
        VStack(spacing: OfficialUISpec.Layout.workspaceListRowGap) {
            NativeWorkspaceRow(
                title: workspace.title,
                expanded: expanded,
                onToggle: onToggle,
                onCreateSession: onCreateSession,
                actions: actions,
                workspaceID: workspace.workspaceId
            )

            if expanded {
                ForEach(sessions.prefix(OfficialUISpec.Layout.workspaceGroupSessionLimit)) { session in
                    NativeSessionRow(
                        session: session,
                        selected: session.sessionId == selectedSessionID,
                        onSelect: { onSelectSession(session.sessionId) },
                        actions: actions
                    )
                }
            }
        }
    }
}

private struct NativeUngroupedWorkspaceGroupView: View {
    let sessions: [SessionSummaryDTO]
    let selectedSessionID: String?
    let expanded: Bool
    let onToggle: () -> Void
    let onSelectSession: (String) -> Void
    let actions: WorkspaceBrowserView.Actions

    var body: some View {
        VStack(spacing: OfficialUISpec.Layout.workspaceListRowGap) {
            NativeWorkspaceRow(
                title: OfficialUISpec.Text.ungrouped,
                expanded: expanded,
                onToggle: onToggle,
                onCreateSession: {},
                actions: actions,
                workspaceID: nil
            )
            if expanded {
                ForEach(sessions.prefix(OfficialUISpec.Layout.workspaceGroupSessionLimit)) { session in
                    NativeSessionRow(
                        session: session,
                        selected: session.sessionId == selectedSessionID,
                        onSelect: { onSelectSession(session.sessionId) },
                        actions: actions
                    )
                }
            }
        }
    }
}

private struct NativeWorkspaceRow: View {
    let title: String
    let expanded: Bool
    let onToggle: () -> Void
    let onCreateSession: () -> Void
    let actions: WorkspaceBrowserView.Actions
    let workspaceID: String?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                OfficialAssetImage(name: expanded ? "icon-folder-open" : "icon-folder-close", template: true)
                    .frame(width: 16, height: 16)
                    .frame(width: 16, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)

            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.primary)
                .lineLimit(1)
            Spacer(minLength: 0)

            if let workspaceID {
                Menu {
                    Button(OfficialUISpec.Text.rename) { actions.renameWorkspace(workspaceID, title) }
                    Button(OfficialUISpec.Text.deleteWorkspace) { actions.deleteWorkspace(workspaceID, title) }
                } label: {
                    OfficialAssetImage(name: "icon-ellipsis", template: true)
                        .frame(width: 16, height: 16)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(OfficialUISpec.Text.workspaceActionsAccessibilityPrefix + title)
            }

            Button(action: onCreateSession) {
                OfficialAssetImage(name: "icon-plus", template: true)
                    .frame(width: 16, height: 16)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(OfficialCircleIconButtonStyle())
        }
        .frame(height: 34)
        .padding(.horizontal, 8)
        .background(OfficialUISpec.Token.base.opacity(0.001), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NativeSessionRow: View {
    let session: SessionSummaryDTO
    let selected: Bool
    let onSelect: () -> Void
    let actions: WorkspaceBrowserView.Actions
    @State private var isHovering = false

    private var status: NativeSessionVisualState {
        NativeSessionVisualState.resolve(session)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                NativeSessionStatusDot(state: status)
                    .frame(width: 16, height: 20)
                Text(sessionTitle(session))
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.trailing, 6)
                if !session.blank {
                    if isHovering {
                        Menu {
                            Button(OfficialUISpec.Text.rename) { actions.renameSession(session.sessionId, sessionTitle(session)) }
                            Button(OfficialUISpec.Text.forkSession) { actions.forkSession(session.sessionId) }
                            Button(OfficialUISpec.Text.archiveSession) { actions.archiveSession(session.sessionId) }
                        } label: {
                            OfficialAssetImage(name: "icon-ellipsis", template: true)
                                .frame(width: 16, height: 16)
                                .frame(width: 20, height: 20)
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel(OfficialUISpec.Text.sessionActionsAccessibilityPrefix + sessionTitle(session))
                    } else {
                        Text(NativeRelativeTime.label(updatedAt: session.updatedAt))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(OfficialUISpec.Token.caption)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .foregroundStyle(OfficialUISpec.Token.primary)
            .frame(height: 32)
            .padding(.horizontal, 8)
            .background(
                selected ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(sessionTitle(session))
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            Color.clear.frame(width: 0, height: 0)
        case .warning:
            ZStack {
                Circle().fill(OfficialUISpec.Token.warningPrimary.opacity(0.1))
                    .frame(width: 10, height: 10)
                Circle().fill(OfficialUISpec.Token.warningPrimary)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 10, height: 10)
            .accessibilityLabel(state.accessibilityLabel)
        case .ongoing:
            ZStack(alignment: .topLeading) {
                ForEach(Array(matrixCells.enumerated()), id: \.offset) { index, point in
                    Rectangle()
                        .fill(OfficialUISpec.Token.businessBlue.opacity(index == 0 ? 1 : index < 4 ? 0.6 : index < 6 ? 0.35 : 0.15))
                        .frame(width: 2, height: 2)
                        .offset(x: point.0, y: point.1)
                }
            }
            .frame(width: 10, height: 10)
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
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(OfficialUISpec.Token.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.leading, 4)
    }
}

private func sessionTitle(_ session: SessionSummaryDTO) -> String {
    session.blank ? OfficialUISpec.Text.newSession : session.displayTitle ?? OfficialUISpec.Text.newSession
}
