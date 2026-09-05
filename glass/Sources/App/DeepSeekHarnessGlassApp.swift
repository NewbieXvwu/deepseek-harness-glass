import AppKit

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI
@testable import GlassSnapshot
#endif
@main
@MainActor
final class DeepSeekHarnessGlassApp: NSObject, NSApplicationDelegate {
    private(set) var windowCoordinator: WindowCoordinator
    private var hostCoordinator: HostLifecycleCoordinator?
    private var menuBarCoordinator: MenuBarCoordinator?

    init(windowCoordinator: WindowCoordinator = WindowCoordinator()) {
        self.windowCoordinator = windowCoordinator
        super.init()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = DeepSeekHarnessGlassApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor [weak self] in
            do {
                if try await SnapshotExporter.exportIfRequested() {
                    NSApp.terminate(nil)
                    return
                }
            } catch {
                FileHandle.standardError.write(Data("snapshot export failed: \(error.localizedDescription)\n".utf8))
                NSApp.terminate(nil)
                return
            }
            self?.launchInteractiveApplication()
        }
    }

    private func launchInteractiveApplication() {
        let presentation = NativeShellPresentation(mode: .welcome)
        windowCoordinator.install(presentation: presentation)
        menuBarCoordinator = MenuBarCoordinator(
            showWindow: { [weak self] in self?.windowCoordinator.showAndFocus() },
            restartHost: { [weak self] in self?.hostCoordinator?.restart() },
            quitApplication: { NSApp.terminate(nil) }
        )
        let coordinator = HostLifecycleCoordinator { [weak self] state in
            self?.applyHostState(state)
        }
        hostCoordinator = coordinator
        coordinator.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowCoordinator.showAndFocus()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hostCoordinator?.stop()
        hostCoordinator = nil
        menuBarCoordinator = nil
    }

    private func applyHostState(_ state: HostLifecycleState) {
        switch state {
        case let .ready(connection):
            windowCoordinator.connectVerifiedHost(connection)
        case .idle, .stopping, .failed, .unverified:
            windowCoordinator.disconnectHost()
        case .startingOwned, .verifying, .recovering:
            break
        }
    }
}
