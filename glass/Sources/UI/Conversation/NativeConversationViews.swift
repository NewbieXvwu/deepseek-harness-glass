import AppKit
import SwiftUI
import UniformTypeIdentifiers

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
struct NativeConversationColumn: View {
    let mode: NativeAppShell.PresentationMode
    let selectedWorkspaceTitle: String?
    let sessionSnapshot: NativeWorkspaceStore.Snapshot
    @ObservedObject var sessionStore: NativeSessionStore
    let jobsPopoverInitiallyOpen: Bool
    let jobsLanguageCode: String?
    let openSession: (String) -> Void

    var body: some View {
        switch mode {
        case .welcome:
            NativeWelcomeSurface(selectedWorkspaceTitle: selectedWorkspaceTitle)
        case .conversation, .tooling, .approval, .question:
            NativeActiveConversationSurface(
                sessionSnapshot: sessionSnapshot,
                sessionStore: sessionStore,
                jobsPopoverInitiallyOpen: jobsPopoverInitiallyOpen,
                jobsLanguageCode: jobsLanguageCode,
                openSession: openSession
            )
        }
    }
}

/// First native transcript surface. The Store provides a session.history
/// baseline plus official mux event deltas; the root remains visually stable
/// for snapshot fixtures whose deterministic conversation mode has no Host.
private struct NativeActiveConversationSurface: View {
    let sessionSnapshot: NativeWorkspaceStore.Snapshot
    @ObservedObject var sessionStore: NativeSessionStore
    let jobsPopoverInitiallyOpen: Bool
    let jobsLanguageCode: String?
    let openSession: (String) -> Void

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p0) {
            NativeConversationHeader(
                presentation: NativeSessionHeaderPresentation(
                    snapshot: sessionSnapshot,
                    sessionID: sessionStore.selectedSessionID,
                    composerIsBlank: sessionStore.items.isEmpty && sessionStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    selectedViewID: sessionStore.selectedViewID
                ),
                jobs: sessionStore.backgroundJobs,
                jobsPopoverInitiallyOpen: jobsPopoverInitiallyOpen,
                jobsLanguageCode: jobsLanguageCode,
                openSession: openSession,
                selectView: sessionStore.selectView
            )
            transcriptBody
            composerTakeover
        }
        .background(OfficialUISpec.Token.base)
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
        } else {
            NativeInteractiveComposerCard(sessionStore: sessionStore)
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
                items: sessionStore.items,
                toolInvocations: sessionStore.toolInvocations,
                isRunning: sessionStore.isRunning,
                selectedToolCallID: sessionStore.selectedToolCallID,
                hasMoreHistory: sessionStore.hasMoreHistory,
                isLoadingOlderHistory: sessionStore.isLoadingOlderHistory,
                loadOlderHistory: sessionStore.loadOlderHistory,
                selectToolCall: sessionStore.selectToolCall
            )
        }
    }
}

private struct NativeTranscriptScrollView: View {
    private enum TimelineItem: Identifiable {
        case message(NativeSessionStore.TranscriptItem)
        case tool(NativeSessionStore.ToolInvocation)

        var id: String {
            switch self {
            case let .message(item): item.id
            case let .tool(invocation): "tool-\(invocation.id)"
            }
        }

        var sequence: Int {
            switch self {
            case let .message(item): item.sequence
            case let .tool(invocation): invocation.sequence
            }
        }
    }

    let items: [NativeSessionStore.TranscriptItem]
    let toolInvocations: [NativeSessionStore.ToolInvocation]
    let isRunning: Bool
    let selectedToolCallID: String?
    let hasMoreHistory: Bool
    let isLoadingOlderHistory: Bool
    let loadOlderHistory: () -> Void
    let selectToolCall: (String?) -> Void

    private var timeline: [TimelineItem] {
        (items.map(TimelineItem.message) + toolInvocations.map(TimelineItem.tool))
            .sorted { $0.sequence < $1.sequence }
    }

    /// Mirrors RC8's follow signature: a streaming delta changes only the tail
    /// signature, leaving all preceding LazyVStack identities untouched.
    private var tailSignature: String {
        let tail = timeline.last
        let textCount: Int
        if case let .message(item)? = tail { textCount = item.text.count }
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
                        case let .message(item):
                            NativeTranscriptBubble(item: item)
                                .id(item.id)
                        case let .tool(invocation):
                            NativeToolRow(
                                invocation: invocation,
                                selected: selectedToolCallID == invocation.id,
                                inspect: { selectToolCall(invocation.id) }
                            )
                            .id(entry.id)
                        }
                    }
                    if isRunning {
                        NativeRunningTurnStatus()
                            .id("running-turn-status")
                    }
                }
                .frame(maxWidth: OfficialUISpec.Layout.chatContentMaximum, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, OfficialUISpec.Layout.chatTranscriptSideClearance)
                .padding(.vertical, OfficialUISpec.Layout.chatTranscriptInset)
            }
            .onChange(of: tailSignature) { _, _ in
                let target = isRunning ? "running-turn-status" : timeline.last?.id
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }
}

private struct NativeTranscriptBubble: View {
    let item: NativeSessionStore.TranscriptItem

    var body: some View {
        Group {
            switch item.role {
            case .user:
                VStack(alignment: .trailing, spacing: OfficialUISpec.Spacing.p2) {
                    HStack {
                        Spacer(minLength: 0)
                        Text(item.text)
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
                    NativeMessageActionRow(text: item.text, time: item.time, clockPosition: .start)
                }
            case .assistant:
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                    Text(item.text)
                        .font(OfficialUISpec.Typography.base16)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    NativeMessageActionRow(text: item.text, time: item.time, clockPosition: .end)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(item.text)
        .accessibilityValue(item.isStreaming ? OfficialUISpec.Text.running : "")
    }
}

struct NativeWelcomeSurface: View {
    let selectedWorkspaceTitle: String?

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(
                OfficialUISpec.Layout.composerMaximum,
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

                    NativeComposerCard(
                        placeholder: selectedWorkspaceTitle == nil
                            ? OfficialUISpec.Text.composerWorkspacePlaceholder
                            : OfficialUISpec.Text.composerHeroPlaceholder,
                        isWorkspaceTrigger: selectedWorkspaceTitle == nil
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

struct NativeComposerCard: View {
    let placeholder: String
    let isWorkspaceTrigger: Bool

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p12) {
            Text(placeholder)
                .font(OfficialUISpec.Typography.base16)
                .foregroundStyle(OfficialUISpec.Token.caption)
                .frame(maxWidth: .infinity, minHeight: OfficialUISpec.Geometry.px48, alignment: .topLeading)
                .padding(.horizontal, OfficialUISpec.Spacing.p16)
                .padding(.top, OfficialUISpec.Spacing.p4)

            HStack(spacing: OfficialUISpec.Spacing.p0) {
                Button(action: {}) {
                    OfficialAssetImage(name: "icon-plus", template: true)
                        .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                        .frame(width: OfficialUISpec.Geometry.px28, height: OfficialUISpec.Geometry.px28)
                }
                .buttonStyle(OfficialComposerIconButtonStyle())
                .disabled(isWorkspaceTrigger)

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

                Button(action: {}) {
                    OfficialAssetImage(name: "icon-send-up", template: true)
                        .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                        .frame(width: OfficialUISpec.Geometry.px34, height: OfficialUISpec.Geometry.px34)
                }
                .buttonStyle(NativeSendButtonStyle(enabled: !isWorkspaceTrigger))
                .disabled(isWorkspaceTrigger)
                .accessibilityLabel(OfficialUISpec.Text.sendMessageAccessibility)
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
    @FocusState private var draftFocused: Bool

    private var sendEnabled: Bool {
        (!sessionStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sessionStore.pendingImages.isEmpty)
            && !sessionStore.isSubmittingPrompt
    }

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p12) {
            if !sessionStore.pendingImages.isEmpty {
                NativePendingImageRail(
                    images: sessionStore.pendingImages,
                    remove: sessionStore.removePendingImage
                )
            }
            ZStack(alignment: .topLeading) {
                if sessionStore.draft.isEmpty {
                    Text(OfficialUISpec.Text.composerDefaultPlaceholder)
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
                    .frame(minHeight: OfficialUISpec.Geometry.px48, maxHeight: OfficialUISpec.Geometry.px336)
                    .padding(.horizontal, OfficialUISpec.Spacing.p10)
                    .padding(.top, OfficialUISpec.Spacing.p2)
                    .onKeyPress { press in
                        guard press.key == .return else { return .ignored }
                        if press.modifiers.contains(.shift) { return .ignored }
                        sessionStore.submitDraft()
                        return .handled
                    }
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
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
                    .accessibilityLabel(OfficialUISpec.Text.composerDefaultPlaceholder)
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
                .accessibilityLabel(OfficialUISpec.Text.commandsAccessibility)

                Spacer(minLength: 0)

                if sessionStore.isRunning {
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
                .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
        }
        .officialLevel2Shadow()
        .onAppear { draftFocused = true }
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
                Text(OfficialUISpec.Text.details)
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

            NativeToolDetailsBody(invocation: selectedInvocation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
    }
}
