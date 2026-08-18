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
    private let windowCoordinator = WindowCoordinator()
    private var hostCoordinator: HostLifecycleCoordinator?
    private var menuBarCoordinator: MenuBarCoordinator?

    static func main() {
        let app = NSApplication.shared
        let delegate = DeepSeekHarnessGlassApp()
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

    func applicationWillTerminate(_ notification: Notification) {
        hostCoordinator?.stop()
        hostCoordinator = nil
        menuBarCoordinator = nil
    }

    private func applyHostState(_ state: HostLifecycleState) {
        switch state {
        case let .ready(connection):
            windowCoordinator.connectVerifiedHost(connection)
        case .idle, .stopping, .failed:
            windowCoordinator.disconnectHost()
        case .startingOwned, .verifying, .recovering:
            break
        }
    }
}
