import AppKit
import Combine
import SwiftUI

/// Main-actor presentation ownership for the native shell. It deliberately
/// holds only window-local presentation state; Host workspace/session truth
/// stays in `NativeWorkspaceStore`.
@MainActor
final class NativeShellPresentation: ObservableObject {
    @Published var mode: NativeAppShell.PresentationMode
    @Published var sidebarPreference: CGFloat = OfficialUISpec.Layout.sidebarDefault
    @Published var detailsPreference: CGFloat = OfficialUISpec.Layout.detailsDefault
    @Published var manuallyCollapsed = false
    @Published var detailsVisible = true

    let workspaceStore: NativeWorkspaceStore

    init(
        mode: NativeAppShell.PresentationMode = .welcome,
        workspaceStore: NativeWorkspaceStore? = nil
    ) {
        self.mode = mode
        self.workspaceStore = workspaceStore ?? NativeWorkspaceStore()
    }
}

/// The real AppKit root controller. Both the running application and the CI
/// snapshot window use this controller directly, so NSSplitViewController owns
/// the complete view-controller tree rather than being embedded in SwiftUI.
@MainActor
final class NativeShellController: NativeSplitViewController {
    private let presentation: NativeShellPresentation
    private var presentationObservation: AnyCancellable?

    init(presentation: NativeShellPresentation) {
        self.presentation = presentation
        super.init(
            sidebar: Self.sidebar(for: presentation, collapsed: presentation.manuallyCollapsed),
            conversation: NativeConversationColumn(mode: presentation.mode),
            details: Self.details(for: presentation),
            sidebarPreference: presentation.sidebarPreference,
            detailsPreference: presentation.detailsPreference,
            sidebarCollapsed: presentation.manuallyCollapsed,
            detailsVisible: presentation.detailsVisible && presentation.mode == .conversation
        )
        presentationObservation = presentation.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.renderPresentation() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLayout() {
        let automaticRail = view.bounds.width < OfficialUISpec.Layout.sidebarAutoCollapse
        let expectedRail = automaticRail || presentation.manuallyCollapsed
        if expectedRail != renderedSidebarCollapsed {
            renderPresentation()
        }
        super.viewDidLayout()
    }

    private func renderPresentation() {
        let automaticRail = isViewLoaded && view.bounds.width < OfficialUISpec.Layout.sidebarAutoCollapse
        let collapsed = automaticRail || presentation.manuallyCollapsed
        update(
            sidebar: Self.sidebar(for: presentation, collapsed: collapsed),
            conversation: NativeConversationColumn(mode: presentation.mode),
            details: Self.details(for: presentation),
            sidebarPreference: presentation.sidebarPreference,
            detailsPreference: presentation.detailsPreference,
            sidebarCollapsed: collapsed,
            detailsVisible: presentation.detailsVisible && presentation.mode == .conversation
        )
    }

    private static func sidebar(
        for presentation: NativeShellPresentation,
        collapsed: Bool
    ) -> NativeSidebarView {
        NativeSidebarView(
            workspaceStore: presentation.workspaceStore,
            collapsed: collapsed,
            setCollapsed: { presentation.manuallyCollapsed = $0 },
            workspaceActions: WorkspaceBrowserView.Actions(),
            onNewSession: {},
            onOpenSettings: {}
        )
    }

    private static func details(for presentation: NativeShellPresentation) -> NativeDetailsView {
        NativeDetailsView(close: { presentation.detailsVisible = false })
    }
}

/// AppKit owns resize dividers and child-controller containment. SwiftUI is
/// confined to the official-spec content surfaces inside the three panes.
@MainActor
class NativeSplitViewController: NSSplitViewController {
    private let sidebarHost: NSHostingController<NativeSidebarView>
    private let conversationHost: NSHostingController<NativeConversationColumn>
    private let detailsHost: NSHostingController<NativeDetailsView>
    private let sidebarItem: NSSplitViewItem
    private let conversationItem: NSSplitViewItem
    private let detailsItem: NSSplitViewItem

    private var sidebarPreference: CGFloat
    private var detailsPreference: CGFloat
    private(set) var renderedSidebarCollapsed: Bool
    private var detailsVisible: Bool
    private var hasAppliedInitialLayout = false

    init(
        sidebar: NativeSidebarView,
        conversation: NativeConversationColumn,
        details: NativeDetailsView,
        sidebarPreference: CGFloat,
        detailsPreference: CGFloat,
        sidebarCollapsed: Bool,
        detailsVisible: Bool
    ) {
        sidebarHost = NSHostingController(rootView: sidebar)
        conversationHost = NSHostingController(rootView: conversation)
        detailsHost = NSHostingController(rootView: details)
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        conversationItem = NSSplitViewItem(viewController: conversationHost)
        detailsItem = NSSplitViewItem(viewController: detailsHost)
        self.sidebarPreference = sidebarPreference
        self.detailsPreference = detailsPreference
        renderedSidebarCollapsed = sidebarCollapsed
        self.detailsVisible = detailsVisible
        super.init(nibName: nil, bundle: nil)

        sidebarItem.canCollapse = false
        conversationItem.canCollapse = false
        detailsItem.canCollapse = true
        detailsItem.collapseBehavior = .useConstraints
        addSplitViewItem(sidebarItem)
        addSplitViewItem(conversationItem)
        addSplitViewItem(detailsItem)
        splitView.dividerStyle = .thin
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !hasAppliedInitialLayout else { return }
        applyLayout()
    }

    func update(
        sidebar: NativeSidebarView,
        conversation: NativeConversationColumn,
        details: NativeDetailsView,
        sidebarPreference: CGFloat,
        detailsPreference: CGFloat,
        sidebarCollapsed: Bool,
        detailsVisible: Bool
    ) {
        sidebarHost.rootView = sidebar
        conversationHost.rootView = conversation
        detailsHost.rootView = details

        let behaviorChanged = renderedSidebarCollapsed != sidebarCollapsed
            || self.detailsVisible != detailsVisible
        self.sidebarPreference = sidebarPreference
        self.detailsPreference = detailsPreference
        renderedSidebarCollapsed = sidebarCollapsed
        self.detailsVisible = detailsVisible
        if behaviorChanged { hasAppliedInitialLayout = false }
        applyLayout()
    }

    private func applyLayout() {
        guard isViewLoaded, splitView.bounds.width > 0 else { return }
        let columns = OfficialColumnLayout.resolve(
            viewport: splitView.bounds.width,
            sidebarPreference: renderedSidebarCollapsed ? 0 : sidebarPreference,
            detailsPreference: detailsVisible ? detailsPreference : 0
        )
        detailsItem.isCollapsed = columns.details == 0
        splitView.setPosition(columns.sidebar, ofDividerAt: 0)
        if columns.details > 0, splitViewItems.count > 2 {
            splitView.setPosition(splitView.bounds.width - columns.details, ofDividerAt: 1)
        }
        hasAppliedInitialLayout = true
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0:
            if renderedSidebarCollapsed { return OfficialUISpec.Layout.sidebarCollapsed }
            return min(max(proposedPosition, OfficialUISpec.Layout.sidebarMinimum), OfficialUISpec.Layout.sidebarMaximum)
        case 1:
            let detailsWidth = splitView.bounds.width - proposedPosition
            let constrained = min(max(detailsWidth, OfficialUISpec.Layout.detailsMinimum), OfficialUISpec.Layout.detailsMaximum)
            let sidebarWidth = renderedSidebarCollapsed ? OfficialUISpec.Layout.sidebarCollapsed : sidebarPreference
            let availableDetails = splitView.bounds.width - sidebarWidth - OfficialUISpec.Layout.centerMinimum
            guard availableDetails >= OfficialUISpec.Layout.detailsMinimum else { return splitView.bounds.width }
            return splitView.bounds.width - min(constrained, availableDetails)
        default:
            return proposedPosition
        }
    }
}
