import AppKit

/// Native boundary for a user-activated external HTTP(S) link from the shared
/// rc.1 Ghost Plane document. The rc.1 client runtime does not expose a
/// trustworthy per-plugin browser-call identity, so this adapter never accepts
/// a caller-supplied plugin ID. Every exact destination is confirmed natively.
@MainActor
public final class GhostPlaneExternalNavigationAdapter {
    public typealias Confirmation = @MainActor (URL) -> Bool
    public typealias Opener = @MainActor (URL) -> Bool

    private let confirmation: Confirmation
    private let opener: Opener

    public init(
        confirmation: @escaping Confirmation = GhostPlaneExternalNavigationAdapter.confirmWithAlert,
        opener: @escaping Opener = { NSWorkspace.shared.open($0) }
    ) {
        self.confirmation = confirmation
        self.opener = opener
    }

    /// Opens only an exact, credential-free HTTP(S) target after the native
    /// confirmation succeeds. The URL is never loaded into the Ghost Plane.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard Self.isAdmitted(url), confirmation(url) else { return false }
        return opener(url)
    }

    public static func isAdmitted(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              url.host != nil
        else { return false }
        return true
    }

    public static func confirmWithAlert(_ url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Open external link?"
        alert.informativeText = url.absoluteString
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Link")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
