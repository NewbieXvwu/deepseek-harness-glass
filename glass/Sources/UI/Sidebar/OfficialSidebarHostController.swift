import AppKit
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// An AppKit-drawn backing surface for the sidebar. `NSHostingController` can
/// otherwise be transparent within a sidebar split item during off-screen
/// rendering, causing the official black chrome to disappear against AppKit's
/// default dark backing store.
@MainActor
final class OfficialSidebarHostController: NSViewController {
    private let hostingController: NSHostingController<NativeSidebarView>

    init(rootView: NativeSidebarView) {
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let canvas = OfficialSidebarCanvasView()
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(
            red: 249 / 255,
            green: 250 / 255,
            blue: 251 / 255,
            alpha: 1
        ).cgColor
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: canvas.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        view = canvas
    }

    func update(rootView: NativeSidebarView) {
        hostingController.rootView = rootView
    }
}

private final class OfficialSidebarCanvasView: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(
            red: 249 / 255,
            green: 250 / 255,
            blue: 251 / 255,
            alpha: 1
        ).setFill()
        dirtyRect.fill()
    }
}
