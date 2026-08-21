import Foundation
import Network

/// Read-only online/offline projection for the Ghost Plane. It exposes no
/// interface name, endpoint, DNS information or monitor object; callers only
/// receive a Boolean and must route it through the typed bridge if needed.
@MainActor
public final class GhostPlaneNetworkStatusAdapter {
    public private(set) var isOnline = false
    public var onStatusChange: ((Bool) -> Void)?

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    public init(monitor: NWPathMonitor = .init(), queue: DispatchQueue = .init(label: "deepseek-harness-glass.network-status")) {
        self.monitor = monitor
        self.queue = queue
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                self.onStatusChange?(online)
            }
        }
    }

    public func start() { monitor.start(queue: queue) }
    public func stop() { monitor.cancel() }
}
