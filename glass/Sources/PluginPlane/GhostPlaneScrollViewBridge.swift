import AppKit
import GlassCore

/// Main-thread adapter from the native transcript scroll view to the one Ghost
/// Plane document. Bounds notifications can arrive much faster than a display
/// refresh, so it retains only the latest source value and flushes at the
/// active screen's maximum refresh cadence. The Core synchronizer remains the
/// authority for epoch/sequence validation.
@MainActor
public final class GhostPlaneScrollViewBridge {
    private weak var scrollView: NSScrollView?
    private weak var host: GhostPlaneWebViewHost?
    private var synchronizer: GhostPlaneScrollSynchronizer
    private var sourceSequence: UInt64 = 0
    private var pendingOffset: Double?
    private var observer: NSObjectProtocol?
    private var displayTimer: Timer?

    public init(scrollView: NSScrollView, host: GhostPlaneWebViewHost, documentEpoch: UInt64) {
        self.scrollView = scrollView
        self.host = host
        synchronizer = .init(documentEpoch: documentEpoch)
        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureNativeOffset() }
        }
        startDisplayCadence()
        captureNativeOffset()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        displayTimer?.invalidate()
    }

    /// Rebinds the adapter when the one document is recreated. Old timer work
    /// is harmless because the Core fence mints a fresh document epoch.
    public func beginDocument(epoch: UInt64) {
        synchronizer = .init(documentEpoch: epoch)
        sourceSequence = 0
        captureNativeOffset()
    }

    private func startDisplayCadence() {
        let maximumFramesPerSecond = Double(scrollView?.window?.screen?.maximumFramesPerSecond ?? 60)
        let interval = 1 / max(1, maximumFramesPerSecond)
        displayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flushLatestOffset() }
        }
        if let displayTimer { RunLoop.main.add(displayTimer, forMode: .common) }
    }

    private func captureNativeOffset() {
        guard let scrollView else { return }
        let offset = Double(scrollView.contentView.bounds.origin.y)
        guard offset.isFinite else { return }
        pendingOffset = offset
    }

    private func flushLatestOffset() {
        guard let offset = pendingOffset else { return }
        pendingOffset = nil
        sourceSequence &+= 1
        guard case .applied(let scalar) = synchronizer.receive(
            sequence: sourceSequence,
            scrollOffset: offset,
            documentEpoch: synchronizer.documentEpoch
        ), let host else { return }
        Task { @MainActor [weak host] in try? await host?.applyScrollOffset(scalar) }
    }
}
