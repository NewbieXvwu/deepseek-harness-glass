import AppKit
import SwiftUI

/// AppKit owns the resize dividers and split persistence semantics; SwiftUI
/// supplies only the three native content surfaces. The sidebar's collapsed
/// state remains a 56px rail rather than a hidden split item.
struct NativeSplitContainer: NSViewControllerRepresentable {
    typealias NSViewControllerType = NativeSplitViewController

    let sidebar: NativeSidebarView
    let conversation: NativeConversationColumn
    let details: NativeDetailsView
    let sidebarPreference: CGFloat
    let detailsPreference: CGFloat
    let sidebarCollapsed: Bool
    let detailsVisible: Bool

    func makeNSViewController(context: Context) -> NativeSplitViewController {
        NativeSplitViewController(
            sidebar: sidebar,
            conversation: conversation,
            details: details,
            sidebarPreference: sidebarPreference,
            detailsPreference: detailsPreference,
            sidebarCollapsed: sidebarCollapsed,
            detailsVisible: detailsVisible
        )
    }

    func updateNSViewController(_ controller: NativeSplitViewController, context: Context) {
        controller.update(
            sidebar: sidebar,
            conversation: conversation,
            details: details,
            sidebarPreference: sidebarPreference,
            detailsPreference: detailsPreference,
            sidebarCollapsed: sidebarCollapsed,
            detailsVisible: detailsVisible
        )
    }
}

final class NativeSplitViewController: NSSplitViewController, NSSplitViewDelegate {
    private let sidebarHost: NSHostingController<NativeSidebarView>
    private let conversationHost: NSHostingController<NativeConversationColumn>
    private let detailsHost: NSHostingController<NativeDetailsView>
    private let sidebarItem: NSSplitViewItem
    private let conversationItem: NSSplitViewItem
    private let detailsItem: NSSplitViewItem

    private var sidebarPreference: CGFloat
    private var detailsPreference: CGFloat
    private var sidebarCollapsed: Bool
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
        self.sidebarCollapsed = sidebarCollapsed
        self.detailsVisible = detailsVisible
        super.init(nibName: nil, bundle: nil)

        sidebarItem.canCollapse = false
        conversationItem.canCollapse = false
        detailsItem.canCollapse = true
        detailsItem.collapseBehavior = .useConstraints

        addSplitViewItem(sidebarItem)
        addSplitViewItem(conversationItem)
        addSplitViewItem(detailsItem)
        splitView.delegate = self
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

        let behaviorChanged = self.sidebarCollapsed != sidebarCollapsed
            || self.detailsVisible != detailsVisible
        self.sidebarPreference = sidebarPreference
        self.detailsPreference = detailsPreference
        self.sidebarCollapsed = sidebarCollapsed
        self.detailsVisible = detailsVisible
        if behaviorChanged { hasAppliedInitialLayout = false }
        applyLayout()
    }

    private func applyLayout() {
        guard isViewLoaded, splitView.bounds.width > 0 else { return }
        let columns = OfficialColumnLayout.resolve(
            viewport: splitView.bounds.width,
            sidebarPreference: sidebarCollapsed ? 0 : sidebarPreference,
            detailsPreference: detailsVisible ? detailsPreference : 0
        )
        detailsItem.isCollapsed = columns.details == 0

        splitView.setPosition(columns.sidebar, ofDividerAt: 0)
        if columns.details > 0, splitViewItems.count > 2 {
            let detailsDividerPosition = splitView.bounds.width - columns.details
            splitView.setPosition(detailsDividerPosition, ofDividerAt: 1)
        }
        hasAppliedInitialLayout = true
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0:
            if sidebarCollapsed { return OfficialUISpec.Layout.sidebarCollapsed }
            return min(max(proposedPosition, OfficialUISpec.Layout.sidebarMinimum), OfficialUISpec.Layout.sidebarMaximum)
        case 1:
            let detailsWidth = splitView.bounds.width - proposedPosition
            let constrained = min(max(detailsWidth, OfficialUISpec.Layout.detailsMinimum), OfficialUISpec.Layout.detailsMaximum)
            let sidebarWidth = sidebarCollapsed ? OfficialUISpec.Layout.sidebarCollapsed : sidebarPreference
            let availableDetails = splitView.bounds.width - sidebarWidth - OfficialUISpec.Layout.centerMinimum
            guard availableDetails >= OfficialUISpec.Layout.detailsMinimum else {
                return splitView.bounds.width
            }
            return splitView.bounds.width - min(constrained, availableDetails)
        default:
            return proposedPosition
        }
    }
}
