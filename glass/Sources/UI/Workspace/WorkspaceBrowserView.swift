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
        var renameWorkspace: (String, String) -> Void = { _, _ in }
        var deleteWorkspace: (String, String) -> Void = { _, _ in }
        var renameSession: (String, String) -> Void = { _, _ in }
        var forkSession: (String) -> Void = { _ in }
        var archiveSession: (String) -> Void = { _ in }
    }

    @State private var searchExpanded = false
    @State private var appliedSearchQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var expandedWorkspaceIDs: Set<String>

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
                scheduleSearch(for: value)
            }
            .onChange(of: store.snapshot.selectedWorkspaceID) { _, workspaceID in
                if let workspaceID { expandedWorkspaceIDs.insert(workspaceID) }
            }
            .onDisappear { searchTask?.cancel() }
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
                    actions: actions
                )
            }

            if !snapshot.ungroupedSessions.isEmpty {
                NativeUngroupedWorkspaceGroupView(
                    sessions: snapshot.ungroupedSessions,
                    selectedSessionID: snapshot.selectedSessionID,
                    expanded: expandedWorkspaceIDs.contains(ungroupedWorkspaceKey),
                    onToggle: { toggleWorkspace(ungroupedWorkspaceKey) },
                    onSelectSession: { actions.selectSession($0, nil) },
                    actions: actions
                )
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = matchingSessions
        if results.isEmpty {
            NativeWorkspaceEmptyState(text: OfficialUISpec.Text.noMatchingSessions)
        } else {
            ForEach(results, id: \.session.sessionId) { result in
                NativeSessionRow(
                    session: result.session,
                    selected: result.session.sessionId == store.snapshot.selectedSessionID,
                    onSelect: { actions.selectSession(result.session.sessionId, result.workspaceID) },
                    actions: actions
                )
            }
        }
    }

    private var searchIsActive: Bool {
        !appliedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingSessions: [(session: SessionSummaryDTO, workspaceID: String?)] {
        let query = appliedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let snapshot = store.snapshot
        let workspaceBySession = Dictionary(uniqueKeysWithValues: snapshot.workspaces.flatMap { workspace in
            workspace.sessionIds.map { ($0, workspace.workspaceId) }
        })
        return snapshot.visibleSessions.compactMap { session in
            let title = sessionTitle(session)
            return title.localizedCaseInsensitiveContains(query)
                ? (session, workspaceBySession[session.sessionId])
                : nil
        }
    }

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.18)) {
            searchExpanded.toggle()
        }
        if !searchExpanded { store.searchQuery = "" }
    }

    private func scheduleSearch(for query: String) {
        searchTask?.cancel()
        searchTask = Task { [query] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            appliedSearchQuery = query
        }
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

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                NativeSessionStatusDot(running: session.running)
                    .frame(width: 16, height: 20)
                Text(sessionTitle(session))
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.trailing, 6)
                if !session.blank {
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
        .accessibilityLabel(sessionTitle(session))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NativeSessionStatusDot: View {
    let running: Bool

    var body: some View {
        Circle()
            .fill(running ? OfficialUISpec.Token.businessBlue : Color.clear)
            .frame(width: running ? 6 : 0, height: running ? 6 : 0)
            .accessibilityLabel(running ? OfficialUISpec.Text.running : OfficialUISpec.Text.idle)
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
