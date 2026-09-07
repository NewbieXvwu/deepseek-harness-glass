import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
@MainActor
struct NativeConversationColumn: View {
    let mode: NativeAppShell.PresentationMode
    let selectedWorkspaceTitle: String?
    let sessionSnapshot: NativeWorkspaceStore.Snapshot
    @ObservedObject var sessionStore: NativeSessionStore
    @ObservedObject var agentPresetStore: NativeAgentPresetStore
    let selectAgentPreset: (String, String) async -> Bool
    let jobsPopoverInitiallyOpen: Bool
    let jobsLanguageCode: String?
    let openSession: (String) -> Void
    /// Comes only from the authenticated Host `session/canOpenWorkspacePath` capability.
    let canOpenProjectPath: Bool
    /// Held by the resident shell in production; default construction keeps
    /// isolated preview/snapshot call sites deterministic.
    let viewRegistry: NativeConversationViewRegistry
    let headerContributions: NativeConversationHeaderContributionRegistry

    init(
        mode: NativeAppShell.PresentationMode,
        selectedWorkspaceTitle: String?,
        sessionSnapshot: NativeWorkspaceStore.Snapshot,
        sessionStore: NativeSessionStore,
        agentPresetStore: NativeAgentPresetStore,
        selectAgentPreset: @escaping (String, String) async -> Bool,
        jobsPopoverInitiallyOpen: Bool,
        jobsLanguageCode: String?,
        openSession: @escaping (String) -> Void,
        canOpenProjectPath: Bool,
        viewRegistry: NativeConversationViewRegistry,
        headerContributions: NativeConversationHeaderContributionRegistry
    ) {
        self.mode = mode
        self.selectedWorkspaceTitle = selectedWorkspaceTitle
        self.sessionSnapshot = sessionSnapshot
        self.sessionStore = sessionStore
        self.agentPresetStore = agentPresetStore
        self.selectAgentPreset = selectAgentPreset
        self.jobsPopoverInitiallyOpen = jobsPopoverInitiallyOpen
        self.jobsLanguageCode = jobsLanguageCode
        self.openSession = openSession
        self.canOpenProjectPath = canOpenProjectPath
        self.viewRegistry = viewRegistry
        self.headerContributions = headerContributions
    }

    private var rootPhase: NativeConversationRootPhase {
        NativeConversationRootPhase.resolve(
            mode: mode,
            sessionID: sessionStore.selectedSessionID,
            sessionPhase: sessionStore.phase,
            snapshot: sessionSnapshot
        )
    }

    var body: some View {
        // Source: RC8 ConversationRoot. A nonblank session whose authority
        // baseline is still landing must not briefly render the active composer
        // before the Host establishes whether the session is hero or docked.
        if rootPhase == .settling {
            Color.clear
                .background(OfficialUISpec.Token.base)
                .accessibilityHidden(true)
        } else {
            switch mode {
            case .welcome:
                NativeWelcomeSurface(
                    selectedWorkspaceTitle: selectedWorkspaceTitle,
                    sessionStore: sessionStore
                )
            case .conversation, .tooling, .approval, .question:
                NativeActiveConversationSurface(
                    sessionSnapshot: sessionSnapshot,
                    sessionStore: sessionStore,
                    agentPresetStore: agentPresetStore,
                    selectAgentPreset: selectAgentPreset,
                    jobsPopoverInitiallyOpen: jobsPopoverInitiallyOpen,
                    jobsLanguageCode: jobsLanguageCode,
                    openSession: openSession,
                    canOpenProjectPath: canOpenProjectPath,
                    viewRegistry: viewRegistry,
                    headerContributions: headerContributions
                )
            }
        }
    }
}

/// Source: RC8 `ConversationRoot` phase selection. This pure mapping keeps the
/// no-session/summary-blank/loading distinction explicit before the resident
/// composer tree is consolidated: a session summary is the only native fact
/// allowed to prove that a loading session belongs on the hero.
enum NativeConversationRootPhase: Equatable {
    case hero
    case settling
    case active

    static func resolve(
        mode: NativeAppShell.PresentationMode,
        sessionID: String?,
        sessionPhase: NativeSessionStore.Phase,
        snapshot: NativeWorkspaceStore.Snapshot
    ) -> Self {
        guard mode != .welcome else { return .hero }
        guard let sessionID else { return .hero }
        let summaryBlank = snapshot.sessions.first(where: { $0.sessionId == sessionID })?.blank == true

        switch sessionPhase {
        case .loading:
            return summaryBlank ? .hero : .settling
        case .idle:
            return summaryBlank ? .hero : .settling
        case .ready, .failed:
            return summaryBlank ? .hero : .active
        }
    }
}

/// Source: RC8 `ConversationRoot`: one root-owned input bar receives either a
/// hero or docked layout posture. `hero` keeps no-workspace as an inert property
/// rather than constructing a second static composer tree, so the bound draft
/// and AppKit focus identity remain owned by the same native control.
enum NativeComposerPresentation: Equatable {
    case hero(workspaceTitle: String?)
    case docked

    var isHero: Bool {
        if case .hero = self { return true }
        return false
    }

    var isWorkspaceTrigger: Bool {
        if case let .hero(workspaceTitle) = self { return workspaceTitle == nil }
        return false
    }

    var placeholder: String {
        switch self {
        case let .hero(workspaceTitle):
            return workspaceTitle == nil
                ? OfficialUISpec.Text.composerWorkspacePlaceholder
                : OfficialUISpec.Text.composerHeroPlaceholder
        case .docked:
            return OfficialUISpec.Text.composerDefaultPlaceholder
        }
    }
}

/// First native transcript surface. The Store provides a session.history
/// baseline plus official mux event deltas; the root remains visually stable
/// for snapshot fixtures whose deterministic conversation mode has no Host.
private struct NativeActiveConversationSurface: View {
    let sessionSnapshot: NativeWorkspaceStore.Snapshot
    @ObservedObject var sessionStore: NativeSessionStore
    @ObservedObject var agentPresetStore: NativeAgentPresetStore
    let selectAgentPreset: (String, String) async -> Bool
    let jobsPopoverInitiallyOpen: Bool
    let jobsLanguageCode: String?
    let openSession: (String) -> Void
    let canOpenProjectPath: Bool
    @ObservedObject var viewRegistry: NativeConversationViewRegistry
    @ObservedObject var headerContributions: NativeConversationHeaderContributionRegistry
    @State private var fullAccessConfirmationOpen = ProcessInfo.processInfo.environment[
        "DSH_GLASS_SNAPSHOT_PERMISSION_CONFIRMATION"
    ] == "1"
    @State private var fullAccessAcknowledged = false

    var body: some View {
        ZStack {
            VStack(spacing: OfficialUISpec.Spacing.p0) {
                NativeConversationHeader(
                    presentation: NativeSessionHeaderPresentation(
                        snapshot: sessionSnapshot,
                        sessionID: sessionStore.selectedSessionID,
                        composerIsBlank: sessionStore.chatNodes.isEmpty && sessionStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        selectedViewID: sessionStore.selectedViewID,
                        viewRegistry: viewRegistry
                    ),
                    jobs: sessionStore.backgroundJobs,
                    jobsPopoverInitiallyOpen: jobsPopoverInitiallyOpen,
                    jobsLanguageCode: jobsLanguageCode,
                    contributionContext: contributionContext,
                    headerContributions: headerContributions,
                    openSession: openSession,
                    selectView: sessionStore.selectView
                )
                if let blankSession {
                    NativeAgentPresetSeat(session: blankSession, store: agentPresetStore) { presetID in
                        await selectAgentPreset(blankSession.sessionId, presetID)
                    }
                    .padding(.horizontal, OfficialUISpec.Spacing.p16)
                    .padding(.vertical, OfficialUISpec.Spacing.p8)
                }
                activeViewBody
                composerDock
            }
            .background(OfficialUISpec.Token.base)

            if fullAccessConfirmationOpen {
                fullAccessConfirmationOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullAccessConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            NativeFullAccessPermissionConfirmation(
                acknowledged: $fullAccessAcknowledged,
                submitting: sessionStore.isSubmittingPermission,
                language: Locale.current.language.languageCode?.identifier ?? "en",
                cancel: {
                    fullAccessConfirmationOpen = false
                    fullAccessAcknowledged = false
                },
                enable: {
                    fullAccessConfirmationOpen = false
                    sessionStore.selectPermissionPreset(PermissionPresetProjection.fullAccessPreset)
                }
            )
        }
    }

    private var blankSession: SessionSummaryDTO? {
        guard let sessionID = sessionStore.selectedSessionID,
              let session = sessionSnapshot.sessions.first(where: { $0.sessionId == sessionID }),
              session.blank
        else { return nil }
        return session
    }

    private var contributionContext: NativeConversationContributionContext {
        .init(
            sessionID: sessionStore.selectedSessionID,
            sessionSnapshot: sessionSnapshot,
            sessionStore: sessionStore,
            openSession: openSession
        )
    }

    @ViewBuilder
    private var activeViewBody: some View {
        if let view = viewRegistry.render(selectedID: sessionStore.selectedViewID, context: contributionContext) {
            view
        } else {
            transcriptBody
        }
    }

    @ViewBuilder
    private var composerDock: some View {
        let components = NativeComposerDockPresentation.components(
            todos: sessionStore.extensionState?.todos,
            goal: sessionStore.extensionState?.goal,
            queuedMessages: sessionStore.extensionState?.queuedMessages ?? [],
            chatNodes: sessionStore.chatNodes,
            locallyClearedGoalID: sessionStore.locallyClearedGoalID,
            hasPendingTakeover: sessionStore.pendingApproval != nil || sessionStore.pendingQuestion != nil
        )
        if sessionStore.pendingApproval == nil, sessionStore.pendingQuestion == nil {
            VStack(spacing: OfficialUISpec.Layout.todoDockContentGap) {
                if components.contains(.todo), let todos = sessionStore.extensionState?.todos {
                    NativeTodoDock(todos: todos)
                }
                if components.contains(.goal), let goal = sessionStore.extensionState?.goal {
                    NativeGoalDock(
                        goal: goal,
                        isSubmitting: sessionStore.isSubmittingGoal,
                        failure: sessionStore.goalActionFailure,
                        edit: sessionStore.editGoal,
                        pause: sessionStore.pauseGoal,
                        resume: sessionStore.resumeGoal,
                        clear: sessionStore.clearGoal
                    )
                }
                if components.contains(.queue), let extensionState = sessionStore.extensionState {
                    NativeQueueDock(
                        rows: extensionState.queuedMessages,
                        isRunning: sessionStore.isRunning,
                        isMutable: NativeQueueDockPresentation.isMutable(extensionState.subagentIdentity),
                        busyItemID: sessionStore.updatingQueueItemID,
                        failure: sessionStore.queueActionFailure,
                        completion: sessionStore.queueActionCompletion,
                        update: sessionStore.updateQueuedMessage
                    )
                }
                if components.contains(.stats), let stats = NativeStatsDockPresentation.project(chatNodes: sessionStore.chatNodes) {
                    NativeStatsDock(stats: stats)
                }
                composerTakeover
            }
        } else {
            composerTakeover
        }
    }

    @ViewBuilder
    private var composerTakeover: some View {
        if let approval = sessionStore.pendingApproval {
            NativeApprovalPanel(
                approval: approval,
                command: sessionStore.command(for: approval),
                submitting: sessionStore.isSubmittingApproval,
                answer: { sessionStore.answerApproval(allowOnce: $0) }
            )
        } else if let question = sessionStore.pendingQuestion {
            NativeQuestionComposer(
                pending: question,
                submitting: sessionStore.isSubmittingQuestion,
                answer: sessionStore.answerQuestion,
                cancel: sessionStore.cancelQuestion
            )
        } else if let route = sessionStore.subagentRoute,
                  route.mode == .oneShot || !route.parentAvailable {
            NativeSubagentReadOnlyComposer(reason: route.mode == .oneShot ? .oneShot : .parentUnavailable)
                .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
                .padding(.bottom, OfficialUISpec.Spacing.p8)
        } else if case let .identity(identity)? = sessionStore.extensionState?.subagentIdentity,
                  identity.mode == .oneShot {
            NativeSubagentReadOnlyComposer(reason: .oneShot)
                .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
                .padding(.bottom, OfficialUISpec.Spacing.p8)
        } else {
            NativeInteractiveComposerCard(
                sessionStore: sessionStore,
                presentation: .docked,
                fullAccessConfirmationOpen: $fullAccessConfirmationOpen,
                fullAccessAcknowledged: $fullAccessAcknowledged
            )
                .frame(maxWidth: OfficialUISpec.Layout.composerMaximum)
                .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
                .padding(.bottom, OfficialUISpec.Spacing.p8)
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        switch sessionStore.phase {
        case .idle:
            Spacer(minLength: 0)
        case .loading:
            VStack(spacing: OfficialUISpec.Spacing.p0) {
                Spacer(minLength: 0)
                Text(OfficialUISpec.Text.chatLoadingHistory)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                Spacer(minLength: 0)
            }
        case .failed:
            // Error copy is rendered only after its official templated surface
            // is added with an RPC error-code mapping; until then, retain the
            // blank transcript rather than exposing transport-private wording.
            Spacer(minLength: 0)
        case .ready:
            NativeTranscriptScrollView(
                chatNodes: sessionStore.chatNodes,
                toolInvocations: sessionStore.toolInvocations,
                isRunning: sessionStore.isRunning,
                selectedToolCallID: sessionStore.selectedToolCallID,
                hasMoreHistory: sessionStore.hasMoreHistory,
                isLoadingOlderHistory: sessionStore.isLoadingOlderHistory,
                loadOlderHistory: sessionStore.loadOlderHistory,
                selectToolCall: sessionStore.selectToolCall,
                deliverablesForAssistant: sessionStore.deliverables,
                openKnownProjectPath: sessionStore.openKnownProjectPath,
                canOpenProjectPath: canOpenProjectPath,
                messageFeedbackItems: sessionStore.messageFeedbackItems,
                isMessageFeedbackAvailable: sessionStore.isMessageFeedbackAvailable,
                failedMessageFeedbackLoad: sessionStore.failedMessageFeedbackLoad,
                isSubmittingMessageFeedback: sessionStore.isSubmittingMessageFeedback,
                messageFeedbackActionFailureCode: sessionStore.messageFeedbackActionFailureCode,
                messageFeedbackMutationMessageID: sessionStore.messageFeedbackMutationMessageID,
                toggleMessageFeedback: sessionStore.toggleMessageFeedback,
                saveMessageFeedbackNote: sessionStore.saveMessageFeedbackNote,
                openSession: openSession
            )
        }
    }
}

private struct NativeTranscriptScrollView: View {
    private enum TimelineItem: Identifiable {
        case chat(ConversationViewNode)
        case tool(NativeSessionStore.ToolInvocation)

        var id: String {
            switch self {
            case let .chat(node): node.key
            case let .tool(invocation): "tool-\(invocation.id)"
            }
        }

        var anchor: Double {
            switch self {
            case let .chat(node): node.anchorSeq ?? .greatestFiniteMagnitude
            case let .tool(invocation): Double(invocation.sequence)
            }
        }
    }

    let chatNodes: [ConversationViewNode]
    let toolInvocations: [NativeSessionStore.ToolInvocation]
    let isRunning: Bool
    let selectedToolCallID: String?
    let hasMoreHistory: Bool
    let isLoadingOlderHistory: Bool
    let loadOlderHistory: () -> Void
    let selectToolCall: (String?) -> Void
    let deliverablesForAssistant: (CoreAssistantNode) -> [String]
    let openKnownProjectPath: (String) -> Void
    let canOpenProjectPath: Bool
    let messageFeedbackItems: [String: MessageFeedbackItemDTO]
    let isMessageFeedbackAvailable: Bool
    let failedMessageFeedbackLoad: Bool
    let isSubmittingMessageFeedback: Bool
    let messageFeedbackActionFailureCode: String?
    let messageFeedbackMutationMessageID: String?
    let toggleMessageFeedback: (String, MessageFeedbackRatingDTO) -> Void
    let saveMessageFeedbackNote: (String, String) -> Void
    let openSession: (String) -> Void

    private var timeline: [TimelineItem] {
        let visibleMessages = chatNodes.compactMap { node -> TimelineItem? in
            guard node.visibility != .hidden,
                  node.data is CoreUserMessageNode || node.data is CoreAssistantNode || node.data is CoreWorkflowRunNode || node.data is CoreTurnMaxTokensNode || node.data is CoreRetryNode || node.data is CoreTurnErrorNode || node.data is CoreCompactionNode
            else { return nil }
            return .chat(node)
        }
        let tools = toolInvocations.map(TimelineItem.tool)
        guard !visibleMessages.isEmpty else { return tools }
        guard !tools.isEmpty else { return visibleMessages }
        // Both inputs are already anchor-ascending (reducer-sorted chat and
        // sorted-insert tool rows); merging keeps every body pass O(n) instead
        // of re-sorting. The tie rule mirrors the previous stable sort.
        var merged: [TimelineItem] = []
        merged.reserveCapacity(visibleMessages.count + tools.count)
        var messageIndex = 0
        var toolIndex = 0
        while messageIndex < visibleMessages.count && toolIndex < tools.count {
            let message = visibleMessages[messageIndex]
            let tool = tools[toolIndex]
            if message.anchor == tool.anchor {
                if message.id < tool.id {
                    merged.append(message)
                    messageIndex += 1
                } else {
                    merged.append(tool)
                    toolIndex += 1
                }
            } else if message.anchor < tool.anchor {
                merged.append(message)
                messageIndex += 1
            } else {
                merged.append(tool)
                toolIndex += 1
            }
        }
        merged.append(contentsOf: visibleMessages[messageIndex...])
        merged.append(contentsOf: tools[toolIndex...])
        return merged
    }

    /// Mirrors RC8's follow signature: a streaming delta changes only the tail
    /// signature, leaving all preceding LazyVStack identities untouched.
    private var tailSignature: String {
        let tail = timeline.last
        let textCount: Int
        if case let .chat(node)? = tail { textCount = NativeConversationNodeRow.textCount(in: node) }
        else { textCount = 0 }
        return "\(tail?.id ?? ""):\(textCount):\(isRunning ? 1 : 0)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OfficialUISpec.Layout.chatMessageGap) {
                    if hasMoreHistory {
                        Button(action: loadOlderHistory) {
                            Text(OfficialUISpec.Text.chatLoadOlder)
                                .font(OfficialUISpec.Typography.xs13)
                                .foregroundStyle(OfficialUISpec.Token.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, OfficialUISpec.Spacing.p6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingOlderHistory)
                        .accessibilityLabel(OfficialUISpec.Text.chatLoadOlder)
                    }
                    ForEach(timeline) { entry in
                        switch entry {
                        case let .chat(node):
                            NativeConversationNodeRow(
                                node: node,
                                deliverablesForAssistant: deliverablesForAssistant,
                                openKnownProjectPath: openKnownProjectPath,
                                canOpenProjectPath: canOpenProjectPath,
                                messageFeedbackItems: messageFeedbackItems,
                                isMessageFeedbackAvailable: isMessageFeedbackAvailable,
                                failedMessageFeedbackLoad: failedMessageFeedbackLoad,
                                isSubmittingMessageFeedback: isSubmittingMessageFeedback,
                                messageFeedbackActionFailureCode: messageFeedbackActionFailureCode,
                                messageFeedbackMutationMessageID: messageFeedbackMutationMessageID,
                                toggleMessageFeedback: toggleMessageFeedback,
                                saveMessageFeedbackNote: saveMessageFeedbackNote,
                                openSession: openSession
                            )
                                .id(node.key)
                        case let .tool(invocation):
                            NativeToolRow(
                                invocation: invocation,
                                selected: selectedToolCallID == invocation.id,
                                openKnownProjectPath: openKnownProjectPath,
                                canOpenProjectPath: canOpenProjectPath,
                                inspect: { selectToolCall(invocation.id) }
                            )
                            .id(entry.id)
                        }
                    }
                    if NativeTranscriptTailPresentation.showsRunningStatus(isRunning: isRunning) {
                        NativeRunningTurnStatus()
                            .id(NativeTranscriptTailPresentation.runningStatusID)
                    }
                }
                .frame(maxWidth: OfficialUISpec.Layout.chatContentMaximum, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, OfficialUISpec.Layout.chatTranscriptSideClearance)
                .padding(.vertical, OfficialUISpec.Layout.chatTranscriptInset)
            }
            .onChange(of: tailSignature) { _, _ in
                let target = NativeTranscriptTailPresentation.scrollTarget(
                    isRunning: isRunning,
                    durableTailID: timeline.last?.id
                )
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }
}

private struct NativeConversationNodeRow: View {
    let node: ConversationViewNode
    let deliverablesForAssistant: (CoreAssistantNode) -> [String]
    let openKnownProjectPath: (String) -> Void
    let canOpenProjectPath: Bool
    let messageFeedbackItems: [String: MessageFeedbackItemDTO]
    let isMessageFeedbackAvailable: Bool
    let failedMessageFeedbackLoad: Bool
    let isSubmittingMessageFeedback: Bool
    let messageFeedbackActionFailureCode: String?
    let messageFeedbackMutationMessageID: String?
    let toggleMessageFeedback: (String, MessageFeedbackRatingDTO) -> Void
    let saveMessageFeedbackNote: (String, String) -> Void
    let openSession: (String) -> Void

    var body: some View {
        Group {
            if let user = node.data as? CoreUserMessageNode {
                userRow(user)
            } else if let assistant = node.data as? CoreAssistantNode {
                assistantRow(assistant)
            } else if let workflow = node.data as? CoreWorkflowRunNode {
                NativeWorkflowRunPanel(workflow: workflow, openSession: openSession)
            } else if node.data is CoreTurnMaxTokensNode {
                NativeTurnMaxTokensNotice()
            } else if let retry = node.data as? CoreRetryNode {
                NativeModelRetryRow(retry: retry)
            } else if let error = node.data as? CoreTurnErrorNode {
                NativeTurnErrorNotice(error: error)
            } else if let compaction = node.data as? CoreCompactionNode {
                NativeCompactionRow(compaction: compaction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(assistantStatus == .running ? OfficialUISpec.Text.running : "")
    }

    static func textCount(in node: ConversationViewNode) -> Int {
        text(in: node).count
    }

    private static func text(in node: ConversationViewNode) -> String {
        if let user = node.data as? CoreUserMessageNode {
            return user.content.compactMap(\.text).joined()
        }
        if let assistant = node.data as? CoreAssistantNode {
            return NativeAssistantTextPresentation.visibleText(assistant)
        }
        return ""
    }

    private var text: String { Self.text(in: node) }
    private var accessibilityText: String { text }
    private var assistantStatus: CoreAssistantNode.Status? { (node.data as? CoreAssistantNode)?.status }

    @ViewBuilder
    private func userRow(_ user: CoreUserMessageNode) -> some View {
        switch user.kind {
        case .context:
            HStack(spacing: OfficialUISpec.Spacing.p6) {
                Image(systemName: "info.circle")
                    .imageScale(.small)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                Text(text)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, OfficialUISpec.Spacing.p4)
            .accessibilityLabel(text)
        case .user, .steering:
            VStack(alignment: .trailing, spacing: OfficialUISpec.Spacing.p2) {
                HStack {
                    Spacer(minLength: 0)
                    Text(text)
                        .font(OfficialUISpec.Typography.base16)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, OfficialUISpec.Spacing.p16)
                        .padding(.vertical, OfficialUISpec.Spacing.p10)
                        .frame(maxWidth: OfficialUISpec.Layout.chatUserMessageMaximum, alignment: .leading)
                        .background(
                            OfficialUISpec.Token.conversationBubble,
                            in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.chatMessageCornerRadius, style: .continuous)
                        )
                }
                if let messageID = NativeMessageCopyPresentation.hostMessageID(for: node) {
                    NativeMessageActionRow(messageID: messageID, text: text, time: user.time, clockPosition: .start)
                }
            }
        }
    }

    private func assistantRow(_ assistant: CoreAssistantNode) -> some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
            if !text.isEmpty {
                NativeMarkdownText(markdown: text, streaming: assistant.status == .running)
                if let messageID = NativeMessageCopyPresentation.hostMessageID(for: assistant) {
                    NativeMessageActionRow(messageID: messageID, text: text, time: assistant.time, clockPosition: .end)
                }
                if isMessageFeedbackAvailable, assistant.status == .settled, let messageID = assistant.messageID {
                    NativeMessageFeedbackActions(
                        item: messageFeedbackItems[messageID],
                        isSubmitting: isSubmittingMessageFeedback,
                        loadFailed: failedMessageFeedbackLoad,
                        actionFailureCode: messageFeedbackMutationMessageID == messageID ? messageFeedbackActionFailureCode : nil,
                        like: { toggleMessageFeedback(messageID, .positive) },
                        dislike: { toggleMessageFeedback(messageID, .negative) },
                        saveNote: { saveMessageFeedbackNote(messageID, $0) }
                    )
                }
                let paths = deliverablesForAssistant(assistant)
                if !paths.isEmpty {
                    NativeProducedFiles(
                        paths: paths,
                        open: openKnownProjectPath,
                        canShowInFolder: canOpenProjectPath
                    )
                }
            }
        }
    }
}

struct NativeWelcomeSurface: View {
    let selectedWorkspaceTitle: String?
    @ObservedObject var sessionStore: NativeSessionStore
    // Hero posture never opens the permission confirmation, but still feeds
    // the shared interactive composer the same bindings as docked posture.
    @State private var fullAccessConfirmationOpen = false
    @State private var fullAccessAcknowledged = false

    var body: some View {
        GeometryReader { geometry in
            // Source: rc.1 ConversationRoot.module.css: the shared chat width is
            // clamp(680px, 64% of the live conversation column, 920px), while
            // InputBar is exactly 32px wider than that content axis.
            let adaptiveContentWidth = min(max(geometry.size.width * 0.64, 680), 920)
            let cardWidth = min(
                adaptiveContentWidth + 32,
                max(0, geometry.size.width - 2 * OfficialUISpec.Layout.composerClearance)
            )

            VStack(spacing: OfficialUISpec.Layout.heroGap) {
                HStack(spacing: OfficialUISpec.Spacing.p10) {
                    OfficialAssetImage(name: "fish-logo")
                        .frame(width: OfficialUISpec.Geometry.px34, height: OfficialUISpec.Geometry.px25)
                    Text(OfficialUISpec.Text.heroHeadline)
                        .font(OfficialUISpec.Typography.heroTitle)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    Text(OfficialUISpec.Text.preview)
                        .font(OfficialUISpec.Typography.codeSmallStrong12)
                        .foregroundStyle(OfficialUISpec.Token.businessBlue)
                        .padding(.horizontal, OfficialUISpec.Spacing.p7)
                        .padding(.vertical, OfficialUISpec.Spacing.p1)
                        .background(OfficialUISpec.Token.businessBlueSoft, in: Capsule())
                        .overlay {
                            Capsule().stroke(OfficialUISpec.Token.businessBlueSoft, lineWidth: 1)
                        }
                        .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: OfficialUISpec.Spacing.p8) {
                    HStack(spacing: OfficialUISpec.Spacing.p2) {
                        NativeHeroChip(
                            asset: "icon-folder-close",
                            text: selectedWorkspaceTitle ?? OfficialUISpec.Text.chooseWorkspace,
                            showsChevron: true
                        )
                        NativeHeroChip(
                            asset: "icon-agent-preset",
                            text: OfficialUISpec.Text.standardMode,
                            showsChevron: true
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, OfficialUISpec.Spacing.p20)

                    NativeInteractiveComposerCard(
                        sessionStore: sessionStore,
                        presentation: .hero(workspaceTitle: selectedWorkspaceTitle),
                        fullAccessConfirmationOpen: $fullAccessConfirmationOpen,
                        fullAccessAcknowledged: $fullAccessAcknowledged
                    )
                }
                .frame(width: cardWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
            .padding(.bottom, OfficialUISpec.Spacing.p32)
        }
        .background(OfficialUISpec.Token.base)
    }
}

private struct NativeHeroChip: View {
    let asset: String
    let text: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: OfficialUISpec.Spacing.p4) {
            OfficialAssetImage(name: asset, template: true)
                .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
            Text(text)
                .font(OfficialUISpec.Typography.xsStrong13)
            if showsChevron {
                OfficialAssetImage(name: "icon-chevron-down", template: true)
                    .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
        }
        .foregroundStyle(OfficialUISpec.Token.primary)
        .padding(.horizontal, OfficialUISpec.Spacing.p8)
        .frame(height: OfficialUISpec.Geometry.px28)
        .background(Color.clear, in: Capsule())
    }
}

private struct NativeHeroComposerControl: View {
    let asset: String
    let title: String

    var body: some View {
        HStack(spacing: OfficialUISpec.Spacing.p2) {
            OfficialAssetImage(name: asset, template: true)
                .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
            Text(title)
            OfficialAssetImage(name: "icon-chevron-down", template: true)
                .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                .foregroundStyle(OfficialUISpec.Token.caption)
        }
        .font(OfficialUISpec.Typography.xsStrong13)
        .foregroundStyle(OfficialUISpec.Token.primary)
        .frame(minHeight: OfficialUISpec.Layout.composerControlHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct NativeInteractiveComposerCard: View {
    @ObservedObject var sessionStore: NativeSessionStore
    let presentation: NativeComposerPresentation
    @Binding var fullAccessConfirmationOpen: Bool
    @Binding var fullAccessAcknowledged: Bool
    @FocusState private var draftFocused: Bool

    private var isWorkspaceTrigger: Bool { presentation.isWorkspaceTrigger }

    private var sendEnabled: Bool {
        !isWorkspaceTrigger
            && (!sessionStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !sessionStore.pendingImages.isEmpty)
            && !sessionStore.isSubmittingPrompt
            && sessionStore.isPromptRouteAvailable
    }

    private var modelBlockedNotice: String? {
        guard !presentation.isHero, !sessionStore.isPromptRouteAvailable else { return nil }
        return OfficialUISpec.LocaleCatalog.value(
            namespace: "ui-model-selection",
            key: "blocked.composer",
            language: "en"
        )
    }

    private var imageAdmissionNotice: String? {
        guard let rejection = sessionStore.imageAdmissionRejection else { return nil }
        let key: String
        switch rejection {
        case .unsupportedContentType, .unsupportedMediaType:
            key = "unsupportedType"
        case .invalidImage, .fileUnreadable:
            key = "loadFailed"
        case .dimensionsExceeded, .pixelsExceeded:
            key = "tooManyPixels"
        case .limitsUnavailable, .tooManyImages, .fileTooLarge, .messageTooLarge:
            key = "dropBlocked"
        }
        return OfficialUISpec.LocaleCatalog.value(namespace: "ui-conversation", key: "image.\(key)", language: "en")
    }

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p12) {
            if !presentation.isHero, !sessionStore.pendingImages.isEmpty {
                NativePendingImageRail(
                    images: sessionStore.pendingImages,
                    remove: sessionStore.removePendingImage
                )
            }
            if !presentation.isHero, let imageAdmissionNotice {
                Text(imageAdmissionNotice)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(imageAdmissionNotice)
            }
            if let modelBlockedNotice {
                Text(modelBlockedNotice)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(modelBlockedNotice)
            }
            ZStack(alignment: .topLeading) {
                if sessionStore.draft.isEmpty {
                    Text(presentation.placeholder)
                        .font(OfficialUISpec.Typography.base16)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                        .padding(.horizontal, OfficialUISpec.Spacing.p16)
                        .padding(.top, OfficialUISpec.Spacing.p8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $sessionStore.draft)
                    .font(OfficialUISpec.Typography.base16)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .scrollContentBackground(.hidden)
                    .focused($draftFocused)
                    .frame(
                        minHeight: isWorkspaceTrigger ? 52 : OfficialUISpec.Geometry.px48,
                        idealHeight: isWorkspaceTrigger ? 52 : nil,
                        maxHeight: isWorkspaceTrigger ? 52 : OfficialUISpec.Geometry.px336
                    )
                    .padding(.horizontal, OfficialUISpec.Spacing.p10)
                    .padding(.top, OfficialUISpec.Spacing.p2)
                    .disabled(isWorkspaceTrigger)
                    .onKeyPress { press in
                        guard !isWorkspaceTrigger, press.key == .return else { return .ignored }
                        if press.modifiers.contains(.shift) { return .ignored }
                        sessionStore.submitDraft()
                        return .handled
                    }
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        guard !isWorkspaceTrigger else { return false }
                        for provider in providers {
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                guard let data = item as? Data,
                                      let url = URL(dataRepresentation: data, relativeTo: nil)
                                else { return }
                                Task { @MainActor in sessionStore.addPendingImage(url) }
                            }
                        }
                        return !providers.isEmpty
                    }
                    .accessibilityLabel(presentation.placeholder)
            }

            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Button(action: {
                    NativeImagePicker.chooseImageURLs().forEach(sessionStore.addPendingImage)
                }) {
                    OfficialAssetImage(name: "icon-plus", template: true)
                        .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                        .frame(width: OfficialUISpec.Geometry.px28, height: OfficialUISpec.Geometry.px28)
                }
                .buttonStyle(OfficialComposerIconButtonStyle())
                .disabled(isWorkspaceTrigger)
                .accessibilityLabel(OfficialUISpec.Text.commandsAccessibility)

                if presentation.isHero {
                    if !isWorkspaceTrigger {
                        NativeHeroComposerControl(
                            asset: "icon-permission-workspace-write",
                            title: OfficialUISpec.Text.fixtureWorkspaceWrite
                        )
                        .padding(.leading, OfficialUISpec.Spacing.p16)
                    }
                    Spacer(minLength: 0)
                    if !isWorkspaceTrigger {
                        HStack(spacing: OfficialUISpec.Spacing.p2) {
                            Text(OfficialUISpec.Text.fixtureModelName)
                            Text(OfficialUISpec.Text.fixtureReasoningEffort)
                                .foregroundStyle(OfficialUISpec.Token.secondary)
                            OfficialAssetImage(name: "icon-chevron-down", template: true)
                                .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                                .foregroundStyle(OfficialUISpec.Token.caption)
                        }
                        .font(OfficialUISpec.Typography.xsStrong13)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .frame(minHeight: OfficialUISpec.Layout.composerControlHeight, alignment: .leading)
                        .padding(.trailing, OfficialUISpec.Spacing.p12)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(OfficialUISpec.Text.fixtureModelName)
                    }
                } else {
                    Spacer(minLength: 0)
                    NativeComposerPermissionSelector(
                        sessionStore: sessionStore,
                        fullAccessConfirmationOpen: $fullAccessConfirmationOpen,
                        fullAccessAcknowledged: $fullAccessAcknowledged
                    )
                    NativeComposerModelSelector(sessionStore: sessionStore)
                    NativeContextMeter(sessionStore: sessionStore)
                }

                if !presentation.isHero, sessionStore.isRunning {
                    Button(action: sessionStore.cancelRunningTurn) {
                        OfficialAssetImage(name: "icon-stop", template: true)
                            .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                            .frame(width: OfficialUISpec.Geometry.px34, height: OfficialUISpec.Geometry.px34)
                    }
                    .buttonStyle(NativeSendButtonStyle(enabled: true))
                    .accessibilityLabel(OfficialUISpec.Text.stopGeneratingAccessibility)
                } else {
                    Button(action: sessionStore.submitDraft) {
                        OfficialAssetImage(name: "icon-send-up", template: true)
                            .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                            .frame(width: OfficialUISpec.Geometry.px34, height: OfficialUISpec.Geometry.px34)
                    }
                    .buttonStyle(NativeSendButtonStyle(enabled: sendEnabled))
                    .disabled(!sendEnabled)
                    .accessibilityLabel(OfficialUISpec.Text.sendMessageAccessibility)
                }
            }
            .padding(.horizontal, OfficialUISpec.Spacing.p8)
            .padding(.bottom, OfficialUISpec.Spacing.p6)
        }
        .padding(.top, OfficialUISpec.Spacing.p10)
        .frame(maxWidth: .infinity, minHeight: OfficialUISpec.Geometry.px112)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous)
                .strokeBorder(
                    isWorkspaceTrigger ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.border,
                    style: StrokeStyle(lineWidth: 1, dash: isWorkspaceTrigger ? [4, 4] : [])
                )
        }
        .officialLevel2Shadow()
        .onAppear {
            if !isWorkspaceTrigger { draftFocused = true }
        }
    }
}

private struct NativePendingImageRail: View {
    let images: [NativeSessionStore.PendingImage]
    let remove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                ForEach(images) { image in
                    ZStack(alignment: .topTrailing) {
                        if let nativeImage = NSImage(data: image.data) {
                            Image(nsImage: nativeImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: OfficialUISpec.Geometry.px56, height: OfficialUISpec.Geometry.px56)
                                .clipShape(RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
                        }
                        Button(action: { remove(image.id) }) {
                            OfficialAssetImage(name: "icon-close", template: true)
                                .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                                .frame(width: OfficialUISpec.Geometry.px22, height: OfficialUISpec.Geometry.px22)
                        }
                        .buttonStyle(OfficialCircleIconButtonStyle())
                        .accessibilityLabel(OfficialUISpec.Text.removePendingImage(name: image.name))
                        .padding(OfficialUISpec.Spacing.p2)
                    }
                }
            }
            .padding(.horizontal, OfficialUISpec.Spacing.p12)
        }
        .accessibilityLabel(OfficialUISpec.Text.pendingImages)
    }
}

private struct NativeSendButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? OfficialUISpec.Token.primaryForeground : OfficialUISpec.Token.caption)
            .background(
                enabled ? OfficialUISpec.Token.businessBlue.opacity(configuration.isPressed ? 0.84 : 1) : OfficialUISpec.Token.businessBlueSoft,
                in: Circle()
            )
    }
}

struct NativeDetailsView: View {
    @ObservedObject var sessionStore: NativeSessionStore
    let close: () -> Void

    private var selectedInvocation: NativeSessionStore.ToolInvocation? {
        guard let selectedID = sessionStore.selectedToolCallID else { return nil }
        return sessionStore.toolInvocations.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p0) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Text(selectedInvocation?.name ?? OfficialUISpec.Text.details)
                    .font(OfficialUISpec.Typography.sStrong14)
                Spacer(minLength: 0)
                Button(action: close) {
                    OfficialAssetImage(name: "icon-close", template: true)
                        .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                        .frame(width: OfficialUISpec.Geometry.px28, height: OfficialUISpec.Geometry.px28)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.closeDetailsAccessibility)
            }
            .frame(height: OfficialUISpec.Geometry.px56)
            .padding(.horizontal, OfficialUISpec.Spacing.p16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(OfficialUISpec.Token.hairline).frame(height: OfficialUISpec.Geometry.px1)
            }

            NativeToolDetailsBody(
                invocation: selectedInvocation,
                selectedCallID: sessionStore.selectedToolCallID
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
    }
}
