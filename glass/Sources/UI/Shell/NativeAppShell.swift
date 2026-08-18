import SwiftUI

/// 首批 native-only 壳：布局与文案完全引用 OfficialUISpec。
/// 这是视觉/布局快照入口，不含 WebView、CSS、JavaScript 或模拟 Host 数据。
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
        darkAppearance: Bool = true
    ) {
        self.mode = mode
        self.viewportWidth = viewportWidth
        self.darkAppearance = darkAppearance
    }

    var body: some View {
        let isNarrow = viewportWidth < OfficialUISpec.Layout.sidebarAutoCollapse
        let sidebarPreference = isNarrow ? 0 : self.sidebarPreference
        let columns = OfficialColumnLayout.resolve(
            viewport: viewportWidth,
            sidebarPreference: sidebarPreference,
            detailsPreference: detailsVisible && mode == .conversation ? detailsPreference : 0
        )

        HStack(spacing: 0) {
            SidebarColumn(collapsed: isNarrow, darkAppearance: darkAppearance)
                .frame(width: columns.sidebar)

            Divider().overlay(OfficialUISpec.Token.separatorThinDark)

            ConversationColumn(mode: mode, darkAppearance: darkAppearance)
                .frame(width: columns.center)

            if columns.details > 0 {
                Divider().overlay(OfficialUISpec.Token.separatorDark)
                DetailsColumn(darkAppearance: darkAppearance) {
                    detailsVisible = false
                }
                .frame(width: columns.details)
            }
        }
        .frame(width: viewportWidth, height: 840)
        .background(darkAppearance ? OfficialUISpec.Token.baseDark : Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, darkAppearance ? .dark : .light)
    }
}

private struct SidebarColumn: View {
    let collapsed: Bool
    let darkAppearance: Bool

    var body: some View {
        VStack(spacing: 0) {
            if collapsed {
                Button(action: {}) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(OfficialIconButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.openSidebarAccessibility)
                .padding(.top, 12)
            } else {
                HStack(spacing: 8) {
                    Text("HARNESS")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(OfficialUISpec.Token.labelPrimaryDark)
                    Spacer(minLength: 0)
                    Button(action: {}) {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(OfficialIconButtonStyle())
                    .accessibilityLabel(OfficialUISpec.Text.collapseSidebarAccessibility)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Button(action: {}) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .medium))
                        Text(OfficialUISpec.Text.newSession)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(OfficialSidebarButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.newSessionAccessibility)
                .padding(.horizontal, 12)
                .padding(.top, 20)

                HStack {
                    Text(OfficialUISpec.Text.workspaces)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.labelSecondaryDark)
                    Spacer(minLength: 0)
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(OfficialIconButtonStyle())
                    .accessibilityLabel(OfficialUISpec.Text.addWorkspace)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
            }

            Spacer(minLength: 0)

            if !collapsed {
                Divider().overlay(OfficialUISpec.Token.separatorThinDark)
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                    Text(OfficialUISpec.Text.preview)
                        .font(.system(size: 13, weight: .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(OfficialUISpec.Token.labelSecondaryDark)
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
        }
        .background(darkAppearance ? OfficialUISpec.Token.sidebarDark : Color(nsColor: .controlBackgroundColor))
    }
}

private struct ConversationColumn: View {
    let mode: NativeAppShell.PresentationMode
    let darkAppearance: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .welcome:
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Text(OfficialUISpec.Text.heroHeadline)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(OfficialUISpec.Token.labelPrimaryDark)
                    Text(OfficialUISpec.Text.preview)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.labelSecondaryDark)
                    Button(OfficialUISpec.Text.chooseWorkspace, action: {})
                        .buttonStyle(OfficialPrimaryButtonStyle())
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
                ComposerBar(placeholder: OfficialUISpec.Text.composerWorkspacePlaceholder, enabled: false)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)

            case .conversation:
                HStack(spacing: 12) {
                    Text(OfficialUISpec.Text.chat)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(OfficialUISpec.Token.labelPrimaryDark)
                .frame(height: 56)
                .padding(.horizontal, 24)
                .overlay(alignment: .bottom) {
                    Divider().overlay(OfficialUISpec.Token.separatorThinDark)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(OfficialUISpec.Text.chat)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(OfficialUISpec.Token.labelSecondaryDark)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }

                ComposerBar(placeholder: OfficialUISpec.Text.composerDefaultPlaceholder, enabled: true)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
        }
        .background(darkAppearance ? OfficialUISpec.Token.baseDark : Color(nsColor: .windowBackgroundColor))
    }
}

private struct DetailsColumn: View {
    let darkAppearance: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(OfficialUISpec.Text.details)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialIconButtonStyle())
                .accessibilityLabel(OfficialUISpec.Text.closeDetailsAccessibility)
            }
            .foregroundStyle(OfficialUISpec.Token.labelPrimaryDark)
            .frame(height: 56)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) {
                Divider().overlay(OfficialUISpec.Token.separatorThinDark)
            }

            Spacer(minLength: 0)
            Text(OfficialUISpec.Text.detailsEmpty)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.labelSecondaryDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .background(darkAppearance ? OfficialUISpec.Token.layerDark : Color(nsColor: .underPageBackgroundColor))
    }
}

private struct ComposerBar: View {
    let placeholder: String
    let enabled: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(OfficialIconButtonStyle())
            .disabled(!enabled)

            Text(placeholder)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.labelTertiaryDark)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)

            Button(action: {}) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(OfficialSendButtonStyle(enabled: enabled))
            .disabled(!enabled)
            .accessibilityLabel(OfficialUISpec.Text.sendMessageAccessibility)
        }
        .padding(10)
        .background(OfficialUISpec.Token.controlDark, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OfficialUISpec.Token.separatorThinDark, lineWidth: 1)
        }
    }
}

private struct OfficialSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.labelPrimaryDark)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.activeFillDark.opacity(0.65) : OfficialUISpec.Token.activeFillDark,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

private struct OfficialPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OfficialUISpec.Token.baseDark)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(OfficialUISpec.Token.brandLight.opacity(configuration.isPressed ? 0.84 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct OfficialIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.labelSecondaryDark)
            .background(configuration.isPressed ? OfficialUISpec.Token.activeFillDark : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 7, style: .continuous))
    }
}

private struct OfficialSendButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? OfficialUISpec.Token.baseDark : OfficialUISpec.Token.labelTertiaryDark)
            .background(
                enabled ? OfficialUISpec.Token.brandLight.opacity(configuration.isPressed ? 0.84 : 1) : OfficialUISpec.Token.activeFillDark,
                in: Circle()
            )
    }
}
