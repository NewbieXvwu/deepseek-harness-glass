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
    private var flushInFlight = false

    public init(scrollView: NSScrollView, host: GhostPlaneWebViewHost, documentEpoch: UInt64) {
        self.scrollView = scrollView
        self.host = host
        synchronizer = .init(documentEpoch: documentEpoch)
        host.beginDocument(epoch: documentEpoch)
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

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        displayTimer?.invalidate()
    }

    /// Rebinds the adapter when the one document is recreated. Old timer work
    /// is harmless because the Core fence mints a fresh document epoch.
    public func beginDocument(epoch: UInt64) {
        synchronizer = .init(documentEpoch: epoch)
        sourceSequence = 0
        pendingOffset = nil
        host?.beginDocument(epoch: epoch)
        captureNativeOffset()
    }

    private func startDisplayCadence() {
        let maximumFramesPerSecond = Double(
            scrollView?.window?.screen?.maximumFramesPerSecond
                ?? NSScreen.main?.maximumFramesPerSecond
                ?? 60
        )
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
        guard !flushInFlight, let offset = pendingOffset else { return }
        pendingOffset = nil
        sourceSequence &+= 1
        guard case .applied(let scalar) = synchronizer.receive(
            sequence: sourceSequence,
            scrollOffset: offset,
            documentEpoch: synchronizer.documentEpoch
        ), let host else { return }
        flushInFlight = true
        Task { @MainActor [weak self, weak host] in
            try? await host?.applyScrollOffset(scalar)
            guard let self else { return }
            self.flushInFlight = false
            if self.pendingOffset != nil { self.flushLatestOffset() }
        }
    }
}
