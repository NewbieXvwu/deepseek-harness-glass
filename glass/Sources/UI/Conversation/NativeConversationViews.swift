import SwiftUI

struct NativeConversationColumn: View {
    let mode: NativeAppShell.PresentationMode
    @ObservedObject var sessionStore: NativeSessionStore

    var body: some View {
        switch mode {
        case .welcome:
            NativeWelcomeSurface()
        case .conversation:
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
            NativeComposerCard(
                placeholder: OfficialUISpec.Text.composerDefaultPlaceholder,
                isWorkspaceTrigger: false
            )
            .frame(maxWidth: OfficialUISpec.Layout.composerMaximum)
            .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
            .padding(.bottom, 8)
        }
        .background(OfficialUISpec.Token.base)
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
            NativeTranscriptScrollView(items: sessionStore.items)
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
    let items: [NativeSessionStore.TranscriptItem]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OfficialUISpec.Layout.chatMessageGap) {
                    ForEach(items) { item in
                        NativeTranscriptBubble(item: item)
                            .id(item.id)
                    }
                }
                .frame(maxWidth: OfficialUISpec.Layout.chatContentMaximum, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
                .padding(.vertical, OfficialUISpec.Layout.chatTranscriptInset)
            }
            .onChange(of: items.last?.id) { _, itemID in
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
                            text: OfficialUISpec.Text.chooseWorkspace,
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
                        placeholder: OfficialUISpec.Text.composerWorkspacePlaceholder,
                        isWorkspaceTrigger: true
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

            HStack(spacing: 8) {
                Button(action: {}) {
                    OfficialAssetImage(name: "icon-plus", template: true)
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialComposerIconButtonStyle())
                .disabled(isWorkspaceTrigger)

                Spacer(minLength: 0)

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
    let close: () -> Void

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

            Spacer(minLength: 0)
            Text(OfficialUISpec.Text.detailsEmpty)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .background(OfficialUISpec.Token.base)
    }
}
