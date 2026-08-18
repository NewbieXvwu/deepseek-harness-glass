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
    @ObservedObject var sessionStore: NativeSessionStore

    var body: some View {
        switch mode {
        case .welcome:
            NativeWelcomeSurface(selectedWorkspaceTitle: selectedWorkspaceTitle)
        case .conversation, .tooling, .approval, .question:
            NativeActiveConversationSurface(sessionStore: sessionStore)
        }
    }
}

/// First native transcript surface. The Store provides a session.history
/// baseline plus official mux event deltas; the root remains visually stable
/// for snapshot fixtures whose deterministic conversation mode has no Host.
private struct NativeActiveConversationSurface: View {
    @ObservedObject var sessionStore: NativeSessionStore

    var body: some View {
        VStack(spacing: 0) {
            NativeConversationHeader()
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
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        switch sessionStore.phase {
        case .idle:
            Spacer(minLength: 0)
        case .loading:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(OfficialUISpec.Text.chatLoadingHistory)
                    .font(.system(size: 13, weight: .regular))
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
                selectedToolCallID: sessionStore.selectedToolCallID,
                hasMoreHistory: sessionStore.hasMoreHistory,
                isLoadingOlderHistory: sessionStore.isLoadingOlderHistory,
                loadOlderHistory: sessionStore.loadOlderHistory,
                selectToolCall: sessionStore.selectToolCall
            )
        }
    }
}

private struct NativeConversationHeader: View {
    var body: some View {
        HStack {
            Text(OfficialUISpec.Text.chat)
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 0)
        }
        .frame(height: 56)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OfficialUISpec.Token.hairline).frame(height: 1)
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
    let selectedToolCallID: String?
    let hasMoreHistory: Bool
    let isLoadingOlderHistory: Bool
    let loadOlderHistory: () -> Void
    let selectToolCall: (String?) -> Void

    private var timeline: [TimelineItem] {
        (items.map(TimelineItem.message) + toolInvocations.map(TimelineItem.tool))
            .sorted { $0.sequence < $1.sequence }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OfficialUISpec.Layout.chatMessageGap) {
                    if hasMoreHistory {
                        Button(action: loadOlderHistory) {
                            Text(OfficialUISpec.Text.chatLoadOlder)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(OfficialUISpec.Token.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
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
                }
                .frame(maxWidth: OfficialUISpec.Layout.chatContentMaximum, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
                .padding(.vertical, OfficialUISpec.Layout.chatTranscriptInset)
            }
            .onChange(of: timeline.last?.id) { _, itemID in
                guard let itemID else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(itemID, anchor: .bottom)
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
                HStack {
                    Spacer(minLength: 0)
                    Text(item.text)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: OfficialUISpec.Layout.chatUserMessageMaximum, alignment: .leading)
                        .background(
                            OfficialUISpec.Token.conversationBubble,
                            in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.chatMessageCornerRadius, style: .continuous)
                        )
                }
            case .assistant:
                Text(item.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack(spacing: 10) {
                    OfficialAssetImage(name: "fish-logo")
                        .frame(width: 34, height: 25)
                    Text(OfficialUISpec.Text.heroHeadline)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    Text(OfficialUISpec.Text.preview)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(OfficialUISpec.Token.businessBlue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(OfficialUISpec.Token.businessBlueSoft, in: Capsule())
                        .overlay {
                            Capsule().stroke(OfficialUISpec.Token.businessBlueSoft, lineWidth: 1)
                        }
                        .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 8) {
                    HStack(spacing: 2) {
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
                    .padding(.leading, 20)

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
            .padding(.bottom, 32)
        }
        .background(OfficialUISpec.Token.base)
    }
}

private struct NativeHeroChip: View {
    let asset: String
    let text: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 4) {
            OfficialAssetImage(name: asset, template: true)
                .frame(width: 16, height: 16)
            Text(text)
                .font(.system(size: 13, weight: .medium))
            if showsChevron {
                OfficialAssetImage(name: "icon-chevron-down", template: true)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
        }
        .foregroundStyle(OfficialUISpec.Token.primary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.clear, in: Capsule())
    }
}

struct NativeComposerCard: View {
    let placeholder: String
    let isWorkspaceTrigger: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(placeholder)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.caption)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            HStack(spacing: 0) {
                Button(action: {}) {
                    OfficialAssetImage(name: "icon-plus", template: true)
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialComposerIconButtonStyle())
                .disabled(isWorkspaceTrigger)

                if !isWorkspaceTrigger {
                    NativeHeroComposerControl(
                        asset: "icon-permission-workspace-write",
                        title: OfficialUISpec.Text.fixtureWorkspaceWrite
                    )
                    .padding(.leading, 16)
                }

                Spacer(minLength: 0)

                if !isWorkspaceTrigger {
                    HStack(spacing: 2) {
                        Text(OfficialUISpec.Text.fixtureModelName)
                        Text(OfficialUISpec.Text.fixtureReasoningEffort)
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                        OfficialAssetImage(name: "icon-chevron-down", template: true)
                            .frame(width: 12, height: 12)
                            .foregroundStyle(OfficialUISpec.Token.caption)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .frame(width: 178, height: 28, alignment: .leading)
                    .padding(.trailing, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(OfficialUISpec.Text.fixtureModelName)
                }

                Button(action: {}) {
                    OfficialAssetImage(name: "icon-send-up", template: true)
                        .frame(width: 16, height: 16)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(NativeSendButtonStyle(enabled: !isWorkspaceTrigger))
                .disabled(isWorkspaceTrigger)
                .accessibilityLabel(OfficialUISpec.Text.sendMessageAccessibility)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous)
                .strokeBorder(
                    isWorkspaceTrigger ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.border,
                    style: StrokeStyle(lineWidth: 1, dash: isWorkspaceTrigger ? [4, 4] : [])
                )
        }
        .shadow(color: OfficialUISpec.Token.businessBlueGlow, radius: 22, y: 8)
    }
}

private struct NativeHeroComposerControl: View {
    let asset: String
    let title: String

    var body: some View {
        HStack(spacing: 2) {
            OfficialAssetImage(name: asset, template: true)
                .frame(width: 16, height: 16)
            Text(title)
            OfficialAssetImage(name: "icon-chevron-down", template: true)
                .frame(width: 12, height: 12)
                .foregroundStyle(OfficialUISpec.Token.caption)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(OfficialUISpec.Token.primary)
        .frame(width: 147, height: 28, alignment: .leading)
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
        VStack(spacing: 12) {
            if !sessionStore.pendingImages.isEmpty {
                NativePendingImageRail(
                    images: sessionStore.pendingImages,
                    remove: sessionStore.removePendingImage
                )
            }
            ZStack(alignment: .topLeading) {
                if sessionStore.draft.isEmpty {
                    Text(OfficialUISpec.Text.composerDefaultPlaceholder)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(OfficialUISpec.Token.caption)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $sessionStore.draft)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .scrollContentBackground(.hidden)
                    .focused($draftFocused)
                    .frame(minHeight: 48, maxHeight: 336)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
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

            HStack(spacing: 8) {
                Button(action: {
                    NativeImagePicker.chooseImageURLs().forEach(sessionStore.addPendingImage)
                }) {
                    OfficialAssetImage(name: "icon-plus", template: true)
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialComposerIconButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.commandsAccessibility)

                Spacer(minLength: 0)

                if sessionStore.isRunning {
                    Button(action: sessionStore.cancelRunningTurn) {
                        OfficialAssetImage(name: "icon-stop", template: true)
                            .frame(width: 16, height: 16)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(NativeSendButtonStyle(enabled: true))
                    .accessibilityLabel(OfficialUISpec.Text.stopGeneratingAccessibility)
                } else {
                    Button(action: sessionStore.submitDraft) {
                        OfficialAssetImage(name: "icon-send-up", template: true)
                            .frame(width: 16, height: 16)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(NativeSendButtonStyle(enabled: sendEnabled))
                    .disabled(!sendEnabled)
                    .accessibilityLabel(OfficialUISpec.Text.sendMessageAccessibility)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous)
                .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
        }
        .shadow(color: OfficialUISpec.Token.businessBlueGlow, radius: 22, y: 8)
        .onAppear { draftFocused = true }
    }
}

private struct NativePendingImageRail: View {
    let images: [NativeSessionStore.PendingImage]
    let remove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    ZStack(alignment: .topTrailing) {
                        if let nativeImage = NSImage(data: image.data) {
                            Image(nsImage: nativeImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        Button(action: { remove(image.id) }) {
                            OfficialAssetImage(name: "icon-close", template: true)
                                .frame(width: 12, height: 12)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(OfficialCircleIconButtonStyle())
                        .accessibilityLabel(OfficialUISpec.Text.removePendingImage(name: image.name))
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .accessibilityLabel(OfficialUISpec.Text.pendingImages)
    }
}

private struct NativeSendButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Color.white : OfficialUISpec.Token.caption)
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(OfficialUISpec.Text.details)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Button(action: close) {
                    OfficialAssetImage(name: "icon-close", template: true)
                        .frame(width: 16, height: 16)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.closeDetailsAccessibility)
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(OfficialUISpec.Token.hairline).frame(height: 1)
            }

            NativeToolDetailsBody(invocation: selectedInvocation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(OfficialUISpec.Token.base)
    }
}
