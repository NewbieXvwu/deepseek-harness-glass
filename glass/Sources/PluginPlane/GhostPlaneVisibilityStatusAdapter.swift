import AppKit

/// Read-only document visibility projection from the native window lifecycle.
/// The Ghost Plane receives at most a Boolean through a future typed bridge;
/// the NSWindow and notification objects remain native-only.
@MainActor
public final class GhostPlaneVisibilityStatusAdapter {
    public private(set) var isVisible: Bool
    public var onStatusChange: ((Bool) -> Void)?

    private weak var window: NSWindow?
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    public init(window: NSWindow, center: NotificationCenter = .default) {
        self.window = window
        self.center = center
        isVisible = window.isVisible && !window.isMiniaturized
        let names: [Notification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            // NSWindow has no didBecomeVisible notification. The coordinator's
            // show-and-focus path makes the retained window key after ordering it
            // front, so this is the observable transition that refreshes the
            // document-visible projection without inventing a window lifecycle.
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
    }

    isolated deinit { observers.forEach { center.removeObserver($0) } }

    public func refresh() {
        guard let window else { update(false); return }
        update(window.isVisible && !window.isMiniaturized)
    }

    private func update(_ next: Bool) {
        guard next != isVisible else { return }
        isVisible = next
        onStatusChange?(next)
    }
}
