import AppKit

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI
@testable import GlassSnapshot
#endif
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var presentation: NativeShellPresentation?

    func install(presentation: NativeShellPresentation) {
        guard window == nil else {
            self.presentation = presentation
            showAndFocus()
            return
        }
        let shellController = NativeShellRootController(presentation: presentation)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 880, height: 600)
        window.contentViewController = shellController
        window.delegate = self
        window.center()
        self.window = window
        self.presentation = presentation
        shellController.refreshForCurrentViewport()
        showAndFocus()
    }

    func showAndFocus() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func connectVerifiedHost(_ connection: HostConnection) {
        presentation?.connectVerifiedHost(connection)
    }

    func disconnectHost() {
        presentation?.disconnectHost()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Retain the historical menu-bar-residency intent: closing the main
        // window hides it, while the status menu remains able to restore it.
        sender.orderOut(nil)
        return false
    }
}
