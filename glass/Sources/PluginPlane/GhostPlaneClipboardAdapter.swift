import AppKit
import GlassCore

/// Plain-text clipboard adapter behind distinct read/write capability prompts.
/// It deliberately exposes neither pasteboard objects nor file/RTF/image bytes
/// to the Ghost Plane boundary.
@MainActor
public final class GhostPlaneClipboardAdapter {
    private let prompts: GhostPlanePermissionPromptPresenter
    private let pasteboard: NSPasteboard

    public init(
        prompts: GhostPlanePermissionPromptPresenter = .init(),
        pasteboard: NSPasteboard = .general
    ) {
        self.prompts = prompts
        self.pasteboard = pasteboard
    }

    public func readPlainText(pluginID: String, displayName: String) -> String? {
        guard prompts.request(pluginID: pluginID, displayName: displayName, capability: .clipboardRead) == .granted else {
            return nil
        }
        return pasteboard.string(forType: .string)
    }

    @discardableResult
    public func writePlainText(_ value: String, pluginID: String, displayName: String) -> Bool {
        guard prompts.request(pluginID: pluginID, displayName: displayName, capability: .clipboardWrite) == .granted else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }
}
