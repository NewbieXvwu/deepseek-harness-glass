import AppKit
import GlassCore

/// Native external-navigation adapter. A plugin cannot send users to an
/// arbitrary scheme: broker approval is remembered per capability, while the
/// user confirms each exact HTTP(S) target before `NSWorkspace` is invoked.
@MainActor
public final class GhostPlaneExternalNavigationAdapter {
    private let prompts: GhostPlanePermissionPromptPresenter
    private let workspace: NSWorkspace

    public init(
        prompts: GhostPlanePermissionPromptPresenter = .init(),
        workspace: NSWorkspace = .shared
    ) {
        self.prompts = prompts
        self.workspace = workspace
    }

    @discardableResult
    public func open(url: URL, pluginID: String, displayName: String) -> Bool {
        guard (url.scheme == "http" || url.scheme == "https"), url.user == nil, url.password == nil else {
            return false
        }
        guard prompts.request(pluginID: pluginID, displayName: displayName, capability: .externalNavigation) == .granted else {
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Open external link?"
        alert.informativeText = url.absoluteString
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Link")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return workspace.open(url)
    }
}
