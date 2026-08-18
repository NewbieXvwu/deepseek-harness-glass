import AppKit
import SwiftUI

/// Native-only DeepSeek Harness shell. The welcome composition mirrors the locked
/// official WebUI's SidebarRoot + EmptyHero + InputBar tree; no WebView is involved.
struct NativeAppShell: View {
    enum PresentationMode: Equatable {
        case welcome
        case conversation
    }

    let mode: PresentationMode
    let viewportWidth: CGFloat
    let darkAppearance: Bool

    @State private var sidebarPreference: CGFloat = OfficialUISpec.Layout.sidebarDefault
    @State private var detailsPreference: CGFloat = OfficialUISpec.Layout.detailsDefault
    @State private var detailsVisible = true

    init(
        mode: PresentationMode = .welcome,
        viewportWidth: CGFloat = 1280,
        darkAppearance: Bool = false
    ) {
        self.mode = mode
        self.viewportWidth = viewportWidth
        self.darkAppearance = darkAppearance
    }

    var body: some View {
        let collapsed = viewportWidth < OfficialUISpec.Layout.sidebarAutoCollapse
        let columns = OfficialColumnLayout.resolve(
            viewport: viewportWidth,
            sidebarPreference: collapsed ? 0 : sidebarPreference,
            detailsPreference: detailsVisible && mode == .conversation ? detailsPreference : 0
        )

        HStack(spacing: 0) {
            SidebarColumn(collapsed: collapsed)
                .frame(width: columns.sidebar)

            Rectangle()
                .fill(OfficialUISpec.Token.hairline)
                .frame(width: 1)

            ConversationColumn(mode: mode)
                .frame(width: max(0, columns.center - 1))

            if columns.details > 0 {
                Rectangle()
                    .fill(OfficialUISpec.Token.hairline)
                    .frame(width: 1)
                DetailsColumn(close: { detailsVisible = false })
                    .frame(width: max(0, columns.details - 1))
            }
        }
        .frame(width: viewportWidth, height: 840)
        .background(OfficialUISpec.Token.base)
        .environment(\.colorScheme, .light)
    }
}

private struct SidebarColumn: View {
    let collapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            if collapsed {
                Button(action: {}) {
                    OfficialAssetImage(name: "fish-logo")
                        .frame(width: 24, height: 18)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(OfficialSidebarIconStyle())
                .accessibilityLabel(OfficialUISpec.Text.openSidebarAccessibility)
                .padding(.top, 12)

                Button(action: {}) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(OfficialSidebarIconStyle())
                .accessibilityLabel(OfficialUISpec.Text.newSessionAccessibility)
                .padding(.top, 12)
            } else {
                HStack(spacing: 8) {
                    OfficialAssetImage(name: "brand-wordmark")
                        .frame(width: 182, height: 24, alignment: .leading)
                    Spacer(minLength: 0)
                    Button(action: {}) {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 14, weight: .regular))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(OfficialSidebarIconStyle())
                    .accessibilityLabel(OfficialUISpec.Text.collapseSidebarAccessibility)
                }
                .frame(height: 60)
                .padding(.leading, 4)
                .padding(.bottom, 8)

                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .regular))
                        Text(OfficialUISpec.Text.newSession)
                            .font(.system(size: 14, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(OfficialNewSessionButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.newSessionAccessibility)
                .padding(.horizontal, 2)
                .padding(.bottom, 8)

                HStack(spacing: 8) {
                    Text(OfficialUISpec.Text.workspaces)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                    Spacer(minLength: 0)
                    SidebarUtilityIcon(symbol: "magnifyingglass", label: "")
                    SidebarUtilityIcon(symbol: "slider.horizontal.3", label: "")
                    SidebarUtilityIcon(symbol: "folder.badge.plus", label: OfficialUISpec.Text.addWorkspace)
                }
                .frame(height: 32)
                .padding(.horizontal, 4)

                Text(OfficialUISpec.Text.noSessionsYet)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }

            Spacer(minLength: 0)

            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: collapsed ? 18 : 14, weight: .regular))
                        .frame(width: collapsed ? 36 : nil, height: 36)
                    if !collapsed {
                        Text(OfficialUISpec.Text.settings)
                            .font(.system(size: 14, weight: .regular))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 36)
            }
            .buttonStyle(OfficialSettingsButtonStyle())
            .padding(.bottom, 4)
        }
        .padding(.horizontal, collapsed ? 10 : OfficialUISpec.Layout.sidebarInlinePadding)
        .padding(.top, collapsed ? 18 : 6)
        .background(OfficialUISpec.Token.sidebar)
    }
}

private struct ConversationColumn: View {
    let mode: NativeAppShell.PresentationMode

    var body: some View {
        switch mode {
        case .welcome:
            OfficialWelcomeSurface()
        case .conversation:
            VStack(spacing: 0) {
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

                Spacer(minLength: 0)

                OfficialComposerCard(
                    placeholder: OfficialUISpec.Text.composerDefaultPlaceholder,
                    isWorkspaceTrigger: false
                )
                .frame(maxWidth: OfficialUISpec.Layout.composerMaximum)
                .padding(.horizontal, OfficialUISpec.Layout.composerClearance)
                .padding(.bottom, 8)
            }
            .background(OfficialUISpec.Token.base)
        }
    }
}

private struct OfficialWelcomeSurface: View {
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
                        OfficialHeroChip(
                            symbol: "folder",
                            text: OfficialUISpec.Text.chooseWorkspace,
                            showsChevron: true
                        )
                        OfficialHeroChip(
                            symbol: "point.3.connected.trianglepath.dotted",
                            text: OfficialUISpec.Text.standardMode,
                            showsChevron: true
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 20)

                    OfficialComposerCard(
                        placeholder: OfficialUISpec.Text.composerWorkspacePlaceholder,
                        isWorkspaceTrigger: true
                    )
                    // The glow is painted behind the fixed-size card. It must not
                    // take part in the stack's proposed width, unlike the first
                    // snapshot implementation where a wide ZStack stretched the card.
                    .background {
                        Ellipse()
                            .fill(OfficialUISpec.Token.businessBlueGlow.opacity(0.44))
                            .frame(width: cardWidth * 1.25, height: 132)
                            .blur(radius: 42)
                            .offset(y: 42)
                            .allowsHitTesting(false)
                    }
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

private struct OfficialHeroChip: View {
    let symbol: String
    let text: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
            Text(text)
                .font(.system(size: 13, weight: .medium))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
        }
        .foregroundStyle(OfficialUISpec.Token.primary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.clear, in: Capsule())
    }
}

private struct DetailsColumn: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(OfficialUISpec.Text.details)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialSidebarIconStyle())
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

private struct OfficialComposerCard: View {
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
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .regular))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialComposerIconStyle())
                .disabled(isWorkspaceTrigger)

                Spacer(minLength: 0)

                Button(action: {}) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(OfficialSendButtonStyle(enabled: !isWorkspaceTrigger))
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
                    isWorkspaceTrigger ? OfficialUISpec.Token.businessBlueSoft : OfficialUISpec.Token.border,
                    style: StrokeStyle(lineWidth: 1, dash: isWorkspaceTrigger ? [4, 4] : [])
                )
        }
        .shadow(color: OfficialUISpec.Token.businessBlueGlow, radius: 22, y: 8)
    }
}

private struct OfficialAssetImage: View {
    let name: String

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SidebarUtilityIcon: View {
    let symbol: String
    let label: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(OfficialSidebarIconStyle())
        .accessibilityLabel(label)
    }
}

private struct OfficialNewSessionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.primary)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.interactiveHover : OfficialUISpec.Token.elevated,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(OfficialUISpec.Token.border, lineWidth: 1)
            }
    }
}

private struct OfficialSidebarIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.secondary)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: Circle()
            )
    }
}

private struct OfficialSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.secondary)
            .background(configuration.isPressed ? OfficialUISpec.Token.interactiveHover : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct OfficialComposerIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.secondary)
            .background(configuration.isPressed ? OfficialUISpec.Token.interactiveHover : Color.clear, in: Circle())
    }
}

private struct OfficialSendButtonStyle: ButtonStyle {
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
