import AppKit
import SwiftUI

/// DeepSeek Harness Glass 的 native-first 入口。
/// 当前里程碑仅挂载官方规格驱动的三栏骨架；Host/transport 将在后续任务中接入。
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            if try SnapshotExporter.exportIfRequested() {
                NSApp.terminate(nil)
                return
            }
        } catch {
            FileHandle.standardError.write(Data("snapshot export failed: \(error.localizedDescription)\n".utf8))
            NSApp.terminate(nil)
            return
        }

        let presentation = NativeShellPresentation(mode: .welcome)
        let shellController = NativeShellController(presentation: presentation)
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
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
