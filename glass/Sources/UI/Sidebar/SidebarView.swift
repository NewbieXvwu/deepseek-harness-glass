import SwiftUI

struct NativeSidebarView: View {
    @ObservedObject var workspaceStore: NativeWorkspaceStore
    let collapsed: Bool
    let setCollapsed: (Bool) -> Void
    let workspaceActions: WorkspaceBrowserView.Actions
    let onNewSession: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if collapsed {
                compactHeader
            } else {
                wideHeader
                newSessionButton
            }

            WorkspaceBrowserView(
                store: workspaceStore,
                collapsed: collapsed,
                requestSidebarExpansion: { setCollapsed(false) },
                actions: workspaceActions
            )

            settingsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, collapsed ? 10 : OfficialUISpec.Layout.sidebarInlinePadding)
        .padding(.top, collapsed ? 18 : 6)
        .background(OfficialUISpec.Token.sidebar)
        .animation(.easeInOut(duration: 0.3), value: collapsed)
    }

    private var compactHeader: some View {
        VStack(spacing: 12) {
            Button(action: { setCollapsed(false) }) {
                OfficialAssetImage(name: "fish-logo")
                    .frame(width: 24, height: 18)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(NativeGlassNavigationButtonStyle())
            .accessibilityLabel(OfficialUISpec.Text.openSidebarAccessibility)

            Button(action: onNewSession) {
                OfficialAssetImage(name: "icon-new-chat", template: true)
                    .frame(width: 18, height: 18)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(OfficialCircleIconButtonStyle(pressedForeground: OfficialUISpec.Token.primary))
            .accessibilityLabel(OfficialUISpec.Text.newSessionAccessibility)
        }
    }

    private var wideHeader: some View {
        HStack(spacing: 8) {
            OfficialAssetImage(name: "brand-wordmark")
                .frame(width: 182, height: 24, alignment: .leading)
            Spacer(minLength: 0)
            Button(action: { setCollapsed(true) }) {
                OfficialAssetImage(name: "icon-panel-left", template: true)
                    .frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(NativeGlassNavigationButtonStyle())
            .accessibilityLabel(OfficialUISpec.Text.collapseSidebarAccessibility)
        }
        .frame(height: 60)
        .padding(.leading, 4)
        .padding(.bottom, 8)
    }

    private var newSessionButton: some View {
        Button(action: onNewSession) {
            HStack(spacing: 6) {
                OfficialAssetImage(name: "icon-new-chat", template: true)
                    .frame(width: 14, height: 14)
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
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 6) {
                OfficialAssetImage(name: "icon-settings", template: true)
                    .frame(width: collapsed ? 18 : 16, height: collapsed ? 18 : 16)
                    .frame(width: collapsed ? 36 : nil, height: 36)
                if !collapsed {
                    Text(OfficialUISpec.Text.settings)
                        .font(.system(size: 14, weight: .regular))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 36)
        }
        .buttonStyle(OfficialSidebarRowButtonStyle())
        .padding(.bottom, 4)
    }
}
