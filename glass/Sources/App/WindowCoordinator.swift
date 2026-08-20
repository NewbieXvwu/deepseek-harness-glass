import AppKit

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI
@testable import GlassSnapshot
#endif

/// App-owned native window policy. It preserves the migrated AppKit geometry
/// while deliberately delegating titlebar, corner avoidance and restoration to
/// NSWindow rather than recreating any web-style transparent window effect.
@MainActor
enum NativeWindowPolicy {
    static let initialContentSize = NSSize(width: 1280, height: 840)
    static let minimumContentSize = NSSize(width: 880, height: 600)
    static let frameAutosaveName = "DeepSeekHarnessGlass.MainWindow"
    static let restorationIdentifier = NSUserInterfaceItemIdentifier("DeepSeekHarnessGlass.MainWindow")
    static let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    static let toolbarStyle: NSWindow.ToolbarStyle = .unifiedCompact

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = toolbarStyle
        window.contentMinSize = minimumContentSize
        window.minSize = minimumContentSize
        window.isRestorable = true
        window.identifier = restorationIdentifier
        return window
    }

    /// Restores only a frame previously saved by this exact native window. A
    /// first launch keeps the fixed visual-capture baseline centered on screen.
    @discardableResult
    static func restoreOrCenter(_ window: NSWindow) -> Bool {
        window.setFrameAutosaveName(frameAutosaveName)
        let restored = window.setFrameUsingName(frameAutosaveName)
        if !restored { window.center() }
        return restored
    }

    static func saveFrame(_ window: NSWindow) {
        window.saveFrame(usingName: frameAutosaveName)
    }
}

/// Pure policy state that makes close-to-menu-bar and reopening behavior
/// independently testable even in an XCTest process without a WindowServer.
enum NativeWindowLifecycle: Equatable {
    case visible
    case hidden
    case minimized

    mutating func hideForClose() { self = .hidden }
    mutating func minimize() { self = .minimized }
    mutating func reveal() { self = .visible }
}

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private(set) var lifecycle: NativeWindowLifecycle = .visible
    private(set) var showAndFocusInvocationCount = 0
    private var presentation: NativeShellPresentation?

    func install(presentation: NativeShellPresentation) {
        guard window == nil else {
            self.presentation = presentation
            showAndFocus()
            return
        }
        let shellController = NativeShellRootController(presentation: presentation)
        let window = NativeWindowPolicy.makeWindow()
        window.contentViewController = shellController
        window.delegate = self
        _ = NativeWindowPolicy.restoreOrCenter(window)
        self.window = window
        self.presentation = presentation
        shellController.refreshForCurrentViewport()
        showAndFocus()
    }

    /// Reopens hidden or minimized windows from the menu bar, Dock or a future
    /// system restoration callback without creating a second shell/controller.
    func showAndFocus() {
        showAndFocusInvocationCount += 1
        lifecycle.reveal()
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func connectVerifiedHost(_ connection: HostConnection) {
        presentation?.connectVerifiedHost(connection)
    }

    func disconnectHost() {
        presentation?.disconnectHost()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        lifecycle.minimize()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        lifecycle.reveal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Preserve resident Host/menu-bar reachability while persisting a native
        // frame for the next open; the window is not destroyed on a red-close.
        NativeWindowPolicy.saveFrame(sender)
        lifecycle.hideForClose()
        sender.orderOut(nil)
        return false
    }
}
