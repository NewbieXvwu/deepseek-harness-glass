import AppKit
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// Hosts official sidebar content without supplying a competing structural
/// background. The enclosing `NSSplitViewItem.sidebar` owns the native material
/// and automatically adapts to Light/Dark, Reduce Transparency and contrast.
@MainActor
final class OfficialSidebarHostController: NSViewController {
    private let hostingController: TransparentHostingController<NativeSidebarView>

    init(rootView: NativeSidebarView) {
        hostingController = TransparentHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.isOpaque = false
        container.layer?.backgroundColor = NSColor.clear.cgColor
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: container.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    func update(rootView: NativeSidebarView) {
        hostingController.rootView = rootView
    }
}
