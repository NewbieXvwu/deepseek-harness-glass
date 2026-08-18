import SwiftUI

/// Native-only DeepSeek Harness shell. AppKit owns the three resizeable panes;
/// SwiftUI owns official-spec content within each pane. No WebView participates
/// in the core shell.
@MainActor
struct NativeAppShell: View {
    enum PresentationMode: Equatable {
        case welcome
        case conversation
    }

    let mode: PresentationMode
    let viewportWidth: CGFloat
    let darkAppearance: Bool

    @StateObject private var workspaceStore: NativeWorkspaceStore
    @State private var sidebarPreference: CGFloat = OfficialUISpec.Layout.sidebarDefault
    @State private var detailsPreference: CGFloat = OfficialUISpec.Layout.detailsDefault
    @State private var manuallyCollapsed = false
    @State private var detailsVisible = true

    init(
        mode: PresentationMode = .welcome,
        viewportWidth: CGFloat = 1280,
        darkAppearance: Bool = false,
        workspaceStore: NativeWorkspaceStore? = nil
    ) {
        self.mode = mode
        self.viewportWidth = viewportWidth
        self.darkAppearance = darkAppearance
        _workspaceStore = StateObject(wrappedValue: workspaceStore ?? NativeWorkspaceStore())
    }

    var body: some View {
        GeometryReader { geometry in
            let autoCollapsed = geometry.size.width < OfficialUISpec.Layout.sidebarAutoCollapse
            let collapsed = autoCollapsed || manuallyCollapsed
            NativeSplitContainer(
                sidebar: NativeSidebarView(
                    workspaceStore: workspaceStore,
                    collapsed: collapsed,
                    setCollapsed: { requested in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            manuallyCollapsed = requested
                        }
                    },
                    workspaceActions: WorkspaceBrowserView.Actions(),
                    onNewSession: {},
                    onOpenSettings: {}
                ),
                conversation: NativeConversationColumn(mode: mode),
                details: NativeDetailsView(close: { detailsVisible = false }),
                sidebarPreference: sidebarPreference,
                detailsPreference: detailsPreference,
                sidebarCollapsed: collapsed,
                detailsVisible: detailsVisible && mode == .conversation
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OfficialUISpec.Token.base)
        .environment(\.colorScheme, darkAppearance ? .dark : .light)
    }
}
