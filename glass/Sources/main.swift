import AppKit
import Combine
import SwiftUI

/// DeepSeek Harness Glass 的 native-first 入口。
/// 原生入口：窗口只装载 AppKit/SwiftUI 壳，业务数据仅通过已验证的
/// DeepSeek Harness Host RPC/SSE 获取。
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var presentation: NativeShellPresentation?
    private var hostController: HarnessHostController?
    private var hostStateObservation: AnyCancellable?

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
        window.makeKeyAndOrderFront(nil)
        shellController.refreshForCurrentViewport()
        self.window = window
        self.presentation = presentation
        startVerifiedHost()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hostStateObservation?.cancel()
        hostStateObservation = nil
        hostController?.stop()
        hostController = nil
    }

    private func startVerifiedHost() {
        do {
            let controller = try HarnessHostController()
            hostController = controller
            hostStateObservation = controller.$state.sink { [weak self] state in
                self?.applyHostState(state)
            }
            controller.start()
        } catch {
            // The view remains the official welcome surface. Host launch errors
            // are retained by its lifecycle/log model instead of custom shell copy.
            presentation?.disconnectHost()
        }
    }

    private func applyHostState(_ state: HostLifecycleState) {
        switch state {
        case let .ready(connection):
            presentation?.connectVerifiedHost(connection)
        case .idle, .stopping, .failed:
            presentation?.disconnectHost()
        case .startingOwned, .verifying, .recovering:
            break
        }
    }
}
