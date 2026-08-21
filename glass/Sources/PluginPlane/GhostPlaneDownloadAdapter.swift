import AppKit
import GlassCore

/// Native save-panel adapter for a plugin-originated download already admitted
/// by the native Host. It never fetches URLs itself and never exposes a file
/// path to the Ghost Plane document.
@MainActor
public final class GhostPlaneDownloadAdapter {
    private let prompts: GhostPlanePermissionPromptPresenter
    private let panelFactory: () -> NSSavePanel

    public init(
        prompts: GhostPlanePermissionPromptPresenter = .init(),
        panelFactory: @escaping () -> NSSavePanel = { NSSavePanel() }
    ) {
        self.prompts = prompts
        self.panelFactory = panelFactory
    }

    public func chooseDestination(
        suggestedName: String,
        pluginID: String,
        displayName: String
    ) -> URL? {
        guard prompts.request(pluginID: pluginID, displayName: displayName, capability: .download) == .granted else {
            return nil
        }
        let panel = panelFactory()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
