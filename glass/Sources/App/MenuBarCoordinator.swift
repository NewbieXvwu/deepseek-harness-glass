import AppKit

@MainActor
final class MenuBarCoordinator: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let showWindow: () -> Void
    private let restartHost: () -> Void
    private let quitApplication: () -> Void

    init(
        showWindow: @escaping () -> Void,
        restartHost: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        self.showWindow = showWindow
        self.restartHost = restartHost
        self.quitApplication = quitApplication
        super.init()
        configureMenu()
    }

    private func configureMenu() {
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "DeepSeek Harness")
        statusItem.button?.toolTip = "DeepSeek Harness"
        let menu = NSMenu()
        menu.addItem(withTitle: "Show DeepSeek Harness", action: #selector(showWindowAction), keyEquivalent: "")
        menu.addItem(withTitle: "Restart Bundled Host", action: #selector(restartHostAction), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeepSeek Harness", action: #selector(quitAction), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func showWindowAction() {
        showWindow()
    }

    @objc private func restartHostAction() {
        restartHost()
    }

    @objc private func quitAction() {
        quitApplication()
    }
}
