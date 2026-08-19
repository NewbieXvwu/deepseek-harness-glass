import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
struct NativeSidebarView: View {
    let workspaceStore: NativeWorkspaceStore
    let collapsed: Bool
    let setCollapsed: (Bool) -> Void
    let workspaceActions: WorkspaceBrowserView.Actions
    let workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog
    let onNewSession: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p0) {
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
                actions: workspaceActions,
                snapshotDialog: workspaceSnapshotDialog
            )

            settingsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, collapsed ? 10 : OfficialUISpec.Layout.sidebarInlinePadding)
        .padding(.top, collapsed ? 18 : 6)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.3), value: collapsed)
    }

    private var compactHeader: some View {
        VStack(spacing: OfficialUISpec.Spacing.p12) {
            Button(action: { setCollapsed(false) }) {
                OfficialAssetImage(name: "fish-logo")
                    .frame(width: OfficialUISpec.Geometry.px24, height: OfficialUISpec.Geometry.px18)
                    .frame(width: OfficialUISpec.Geometry.px36, height: OfficialUISpec.Geometry.px36)
            }
            .buttonStyle(NativeGlassNavigationButtonStyle())
            .accessibilityLabel(OfficialUISpec.Text.openSidebarAccessibility)

            Button(action: onNewSession) {
                OfficialAssetImage(name: "icon-new-chat", template: true)
                    .frame(width: OfficialUISpec.Geometry.px18, height: OfficialUISpec.Geometry.px18)
                    .frame(width: OfficialUISpec.Geometry.px36, height: OfficialUISpec.Geometry.px36)
            }
            .buttonStyle(OfficialCircleIconButtonStyle(pressedForeground: OfficialUISpec.Token.primary))
            .accessibilityLabel(OfficialUISpec.Text.newSessionAccessibility)
        }
    }

    private var wideHeader: some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            OfficialAssetImage(name: "brand-wordmark")
                .frame(
                    width: OfficialUISpec.Layout.sidebarWordmarkWidth,
                    height: OfficialUISpec.Layout.sidebarWordmarkHeight,
                    alignment: .leading
                )
            Spacer(minLength: 0)
            Button(action: { setCollapsed(true) }) {
                OfficialAssetImage(name: "icon-panel-left", template: true)
                    .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                    .frame(width: OfficialUISpec.Geometry.px28, height: OfficialUISpec.Geometry.px28)
            }
            .buttonStyle(NativeGlassNavigationButtonStyle())
            .accessibilityLabel(OfficialUISpec.Text.collapseSidebarAccessibility)
        }
        .frame(height: OfficialUISpec.Geometry.px60)
        .padding(.leading, OfficialUISpec.Spacing.p4)
        .padding(.bottom, OfficialUISpec.Spacing.p8)
    }

    private var newSessionButton: some View {
        Button(action: onNewSession) {
            HStack(spacing: OfficialUISpec.Spacing.p6) {
                OfficialAssetImage(name: "icon-new-chat", template: true)
                    .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                Text(OfficialUISpec.Text.newSession)
                    .font(OfficialUISpec.Typography.sStrong14)
                Spacer(minLength: 0)
            }
            .frame(height: OfficialUISpec.Geometry.px36)
            .padding(.horizontal, OfficialUISpec.Spacing.p16)
        }
        .buttonStyle(OfficialNewSessionButtonStyle())
        .accessibilityLabel(OfficialUISpec.Text.newSessionAccessibility)
        .padding(.horizontal, OfficialUISpec.Spacing.p2)
        .padding(.bottom, OfficialUISpec.Spacing.p8)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: OfficialUISpec.Spacing.p6) {
                OfficialAssetImage(name: "icon-settings", template: true)
                    .frame(width: collapsed ? 18 : 16, height: collapsed ? 18 : 16)
                    .frame(width: collapsed ? 36 : nil, height: OfficialUISpec.Geometry.px36)
                if !collapsed {
                    Text(OfficialUISpec.Text.settings)
                        .font(OfficialUISpec.Typography.s14)
                }
                Spacer(minLength: 0)
            }
            .frame(height: OfficialUISpec.Geometry.px36)
        }
        .buttonStyle(OfficialSidebarRowButtonStyle())
        .padding(.bottom, OfficialUISpec.Spacing.p4)
    }
}
