import AppKit
import GlassCore

/// Native-only first-request presenter for Ghost Plane capabilities. It owns no
/// platform action: callers must obtain `.granted` first, then invoke their
/// separate notification/pasteboard/panel adapter. This preserves the broker's
/// no-preauthorization and revocation semantics.
@MainActor
public final class GhostPlanePermissionPromptPresenter {
    private var broker: GhostPlanePermissionBroker

    public init(broker: GhostPlanePermissionBroker = .init()) { self.broker = broker }

    public func request(pluginID: String, displayName: String, capability: GhostPlanePermissionBroker.Capability) -> GhostPlanePermissionBroker.Decision {
        let current = broker.decision(for: pluginID, capability: capability)
        guard current == .needsNativePrompt else { return current }
        let alert = NSAlert()
        alert.messageText = "Allow \(displayName) to \(description(for: capability))?"
        alert.informativeText = "This decision applies only to this plugin and capability. You can revoke it later in Settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        let resolution: GhostPlanePermissionBroker.Resolution = alert.runModal() == .alertFirstButtonReturn ? .grant : .deny
        return broker.resolveFirstRequest(pluginID: pluginID, capability: capability, resolution: resolution)
    }

    @discardableResult
    public func revoke(pluginID: String, capability: GhostPlanePermissionBroker.Capability) -> Bool {
        broker.revoke(pluginID: pluginID, capability: capability)
    }

    public var records: [GhostPlanePermissionBroker.Record] { broker.records }

    private func description(for capability: GhostPlanePermissionBroker.Capability) -> String {
        switch capability {
        case .notifications: return "send notifications"
        case .clipboardRead: return "read the clipboard"
        case .clipboardWrite: return "write to the clipboard"
        case .download: return "save a download"
        case .openFilePicker: return "open a file picker"
        case .externalNavigation: return "open an external link"
        }
    }
}
