import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
struct NativeSidebarView: View {
    let workspaceStore: NativeWorkspaceStore
    /// Source: RC8 `host.describe.home`; absent until the verified Host answers.
    let hostHome: String?
    /// Source for the native settings trigger's expanded accessibility value.
    let settingsPresented: Bool
    let collapsed: Bool
    let setCollapsed: (Bool) -> Void
    let workspaceActions: WorkspaceBrowserView.Actions
    let workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog
    let onNewSession: () -> Void
    let onOpenSettings: () -> Void

    init(
        workspaceStore: NativeWorkspaceStore,
        hostHome: String? = nil,
        settingsPresented: Bool = false,
        collapsed: Bool,
        setCollapsed: @escaping (Bool) -> Void,
        workspaceActions: WorkspaceBrowserView.Actions,
        workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog,
        onNewSession: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.workspaceStore = workspaceStore
        self.hostHome = hostHome
        self.settingsPresented = settingsPresented
        self.collapsed = collapsed
        self.setCollapsed = setCollapsed
        self.workspaceActions = workspaceActions
        self.workspaceSnapshotDialog = workspaceSnapshotDialog
        self.onNewSession = onNewSession
        self.onOpenSettings = onOpenSettings
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigationGlassNamespace

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
                hostHome: hostHome,
                collapsed: collapsed,
                requestSidebarExpansion: { setCollapsed(false) },
                actions: workspaceActions,
                snapshotDialog: workspaceSnapshotDialog
            )
            .frame(maxHeight: .infinity, alignment: .top)

            settingsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.leading, collapsed ? 10 : OfficialUISpec.Layout.sidebarNativeExpandedLeadingInset)
        .padding(.trailing, collapsed ? 10 : OfficialUISpec.Layout.sidebarInlinePadding)
        .padding(.top, collapsed ? 18 : 6)
        .background(Color.clear)
        .animation(NativeSidebarCollapseAnimation.transition(reduceMotion: reduceMotion), value: collapsed)
    }

    private var compactHeader: some View {
        GlassEffectContainer(spacing: OfficialUISpec.Spacing.p12) {
            VStack(spacing: OfficialUISpec.Spacing.p12) {
                Button(action: { setCollapsed(false) }) {
                    OfficialAssetImage(name: "fish-logo")
                        .frame(width: OfficialUISpec.Geometry.px24, height: OfficialUISpec.Geometry.px18)
                        .frame(width: OfficialUISpec.Geometry.px36, height: OfficialUISpec.Geometry.px36)
                }
                .buttonStyle(NativeGlassNavigationButtonStyle())
                .glassEffectID("sidebar-navigation-toggle", in: navigationGlassNamespace)
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
    }

    private var wideHeader: some View {
        GlassEffectContainer(spacing: OfficialUISpec.Spacing.p12) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                wideBrand
                    .layoutPriority(1)
                Button(action: { setCollapsed(true) }) {
                    OfficialAssetImage(name: "icon-panel-left", template: true)
                        .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                        .frame(width: OfficialUISpec.Geometry.px28, height: OfficialUISpec.Geometry.px28)
                }
                .buttonStyle(NativeGlassNavigationButtonStyle())
                .glassEffectID("sidebar-navigation-toggle", in: navigationGlassNamespace)
                .accessibilityLabel(OfficialUISpec.Text.collapseSidebarAccessibility)
            }
        }
        .frame(height: OfficialUISpec.Layout.sidebarLogoRowHeight)
        .padding(.leading, OfficialUISpec.Spacing.p4)
        .padding(.bottom, OfficialUISpec.Spacing.p8)
    }

    private var wideBrand: some View {
        Button(action: onNewSession) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                OfficialAssetImage(name: "fish-logo")
                    .frame(
                        width: OfficialUISpec.Layout.sidebarBrandMarkSize,
                        height: OfficialUISpec.Layout.sidebarBrandMarkSize
                    )
                Text(OfficialUISpec.Text.sidebarFallbackBrand)
                    .font(OfficialUISpec.Typography.sidebarBrand17)
                    .lineLimit(1)
                Text(OfficialUISpec.sidebarBuildRevision)
                    .font(OfficialUISpec.Typography.sidebarBuildBadge8)
                    .foregroundStyle(OfficialUISpec.Token.primaryForeground)
                    .padding(.horizontal, OfficialUISpec.Spacing.p4)
                    .frame(height: OfficialUISpec.Layout.sidebarBuildBadgeHeight)
                    .background(
                        OfficialUISpec.Token.primary,
                        in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r3, style: .continuous)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(OfficialUISpec.Text.newSessionAccessibility)
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
            .frame(height: OfficialUISpec.Layout.sidebarNewSessionHeight)
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
        .accessibilityLabel(OfficialUISpec.Text.settings)
        .accessibilityValue(settingsPresented ? "true" : "false")
        .padding(.leading, collapsed ? OfficialUISpec.Spacing.p0 : OfficialUISpec.Layout.sidebarNativeExpandedFooterLeadingAdjustment)
        .padding(.bottom, OfficialUISpec.Spacing.p4)
    }
}
