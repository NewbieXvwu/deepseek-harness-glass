import Combine
import Foundation

/// Lifecycle owner for an already-running local Host. The caller must provide
/// the Host's printed launch URL, including its process token. This controller
/// never probes bare ports and never owns or terminates the external process.
@MainActor
final class ExternalHarnessHostController: ObservableObject {
    @Published private(set) var state: HostLifecycleState = .idle

    private let diagnostics = HostDiagnosticRecorder(dshHome: "external")
    private var descriptor: HostLaunchDescriptor?
    private var authenticatedHost: AuthenticatedHostSession?
    private var connectionTask: Task<Void, Never>?
    private var eventTerminationTask: Task<Void, Never>?

    deinit {
        connectionTask?.cancel()
        eventTerminationTask?.cancel()
        authenticatedHost?.invalidate()
    }

    func attach(launchURL: URL) {
        stop()
        let descriptor: HostLaunchDescriptor
        do {
            descriptor = try HostLaunchDescriptor(url: launchURL)
        } catch {
            state = .failed(HostFailure(
                kind: .verificationFailed,
                message: "External DeepSeek Harness Host launch URL is invalid.",
                exitStatus: nil,
                logPath: ""
            ))
            return
        }
        self.descriptor = descriptor
        state = .authenticating(descriptor.cleanBaseURL)
        authenticateAndConnect(descriptor)
    }

    func stop() {
        connectionTask?.cancel()
        connectionTask = nil
        eventTerminationTask?.cancel()
        eventTerminationTask = nil
        if case let .ready(connection) = state {
            Task { await connection.context.remote.closeStreams() }
        }
        authenticatedHost?.invalidate()
        authenticatedHost = nil
        descriptor = nil
        state = .idle
    }

    private func authenticateAndConnect(_ descriptor: HostLaunchDescriptor) {
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            do {
                let authenticatedHost = try await HostAuthBootstrap.authenticate(descriptor)
                guard !Task.isCancelled, let self, self.descriptor?.launchURL == descriptor.launchURL else {
                    authenticatedHost.invalidate()
                    return
                }
                self.authenticatedHost = authenticatedHost
                self.state = .connecting(authenticatedHost.baseURL)
                let remote = RemoteConnection(authenticatedHost: authenticatedHost)
                let events = try await remote.connectEvents()
                guard !Task.isCancelled, self.authenticatedHost?.urlSession === authenticatedHost.urlSession else {
                    await remote.closeStreams()
                    return
                }
                await self.publishReady(authenticatedHost: authenticatedHost, remote: remote, events: events)
            } catch {
                guard !Task.isCancelled, let self else { return }
                await self.diagnostics.recordRPCError(error)
                self.authenticatedHost?.invalidate()
                self.authenticatedHost = nil
                self.state = .failed(HostFailure(
                    kind: .verificationFailed,
                    message: "External DeepSeek Harness Host could not authenticate or establish Remote readiness: \(error.localizedDescription)",
                    exitStatus: nil,
                    logPath: ""
                ))
            }
        }
    }

    private func publishReady(
        authenticatedHost: AuthenticatedHostSession,
        remote: RemoteConnection,
        events: RemoteEventChannel
    ) async {
        guard self.authenticatedHost?.urlSession === authenticatedHost.urlSession,
              descriptor?.cleanBaseURL == authenticatedHost.baseURL
        else {
            await remote.closeStreams()
            return
        }
        await diagnostics.recordConnected(endpoint: authenticatedHost.baseURL, pid: nil, generation: events.generation)
        let context = HostConnectionContext(
            authenticatedHost: authenticatedHost,
            remote: remote,
            events: events,
            diagnostics: diagnostics
        )
        let connection = HostConnection(
            endpoint: authenticatedHost.baseURL,
            context: context,
            startedAt: Date(),
            diagnostics: diagnostics
        )
        state = .ready(connection)
        monitorEventTermination(for: connection)
    }

    private func monitorEventTermination(for connection: HostConnection) {
        eventTerminationTask?.cancel()
        let generation = connection.context.generation
        eventTerminationTask = Task { [weak self] in
            let termination = await connection.context.events.termination.value
            guard !Task.isCancelled else { return }
            self?.handleEventTermination(termination, generation: generation)
        }
    }

    private func handleEventTermination(
        _ termination: RemoteEventTermination,
        generation: RemoteConnectionGeneration
    ) {
        guard case let .ready(connection) = state,
              connection.context.generation == generation,
              authenticatedHost?.urlSession === connection.context.authenticatedHost.urlSession
        else { return }
        switch termination {
        case .cancelled:
            return
        case .ended, .failed:
            reconnectRemote(from: connection)
        }
    }

    private func reconnectRemote(from connection: HostConnection) {
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            guard let self,
                  let authenticatedHost = self.authenticatedHost,
                  authenticatedHost.urlSession === connection.context.authenticatedHost.urlSession
            else { return }
            var retryDelayNanoseconds: UInt64 = 200_000_000
            for attempt in 1...6 {
                guard !Task.isCancelled,
                      self.authenticatedHost?.urlSession === authenticatedHost.urlSession
                else { return }
                self.state = attempt == 1 ? .connecting(authenticatedHost.baseURL) : .recovering(attempt: attempt)
                do {
                    let remote = RemoteConnection(authenticatedHost: authenticatedHost)
                    let events = try await remote.connectEvents()
                    guard !Task.isCancelled else {
                        await remote.closeStreams()
                        return
                    }
                    await self.publishReady(authenticatedHost: authenticatedHost, remote: remote, events: events)
                    return
                } catch {
                    await self.diagnostics.recordRPCError(error)
                    guard attempt < 6 else { break }
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    retryDelayNanoseconds = min(retryDelayNanoseconds * 2, 3_000_000_000)
                }
            }
            guard !Task.isCancelled else { return }
            self.authenticatedHost?.invalidate()
            self.authenticatedHost = nil
            self.state = .failed(HostFailure(
                kind: .verificationFailed,
                message: "External DeepSeek Harness Host Remote carrier recovery failed after repeated backoff.",
                exitStatus: nil,
                logPath: ""
            ))
        }
    }
}
