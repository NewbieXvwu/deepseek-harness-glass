import AppKit
import GlassCore

/// Native file-picker adapter. Selected URLs are deliberately returned only to
/// native callers, which must run their existing attachment-admission pipeline
/// before an opaque attachment ID can reach any Ghost Plane event.
@MainActor
public final class GhostPlaneFilePickerAdapter {
    private let prompts: GhostPlanePermissionPromptPresenter
    private let panelFactory: () -> NSOpenPanel

    public init(
        prompts: GhostPlanePermissionPromptPresenter = .init(),
        panelFactory: @escaping () -> NSOpenPanel = { NSOpenPanel() }
    ) {
        self.prompts = prompts
        self.panelFactory = panelFactory
    }

    public func chooseFiles(pluginID: String, displayName: String) -> [URL] {
        guard prompts.request(pluginID: pluginID, displayName: displayName, capability: .openFilePicker) == .granted else {
            return []
        }
        let panel = panelFactory()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
