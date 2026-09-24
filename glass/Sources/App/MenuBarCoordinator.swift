import AppKit

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI
@testable import GlassSnapshot
#endif
@MainActor
final class MenuBarCoordinator: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let showWindow: () -> Void
    private let restartHost: () -> Void
    private let attachExternalHost: (URL) -> Void
    private let quitApplication: () -> Void

    init(
        showWindow: @escaping () -> Void,
        restartHost: @escaping () -> Void,
        attachExternalHost: @escaping (URL) -> Void,
        quitApplication: @escaping () -> Void
    ) {
        self.showWindow = showWindow
        self.restartHost = restartHost
        self.attachExternalHost = attachExternalHost
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
        menu.addItem(withTitle: "Attach External Host…", action: #selector(attachExternalHostAction), keyEquivalent: "")
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

    @objc private func attachExternalHostAction() {
        let field = NSTextField(string: "")
        field.placeholderString = "http://127.0.0.1:3080/?token=…"
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 24)

        let alert = NSAlert()
        alert.messageText = "Attach External DeepSeek Harness Host"
        alert.informativeText = "Paste the complete dsh web launch URL, including its token."
        alert.accessoryView = field
        alert.addButton(withTitle: "Attach")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), !value.isEmpty else {
            let errorAlert = NSAlert()
            errorAlert.alertStyle = .warning
            errorAlert.messageText = "Invalid Host URL"
            errorAlert.informativeText = "Paste the complete URL printed after “dsh web:”."
            errorAlert.runModal()
            return
        }
        attachExternalHost(url)
    }

    @objc private func quitAction() {
        quitApplication()
    }
}
