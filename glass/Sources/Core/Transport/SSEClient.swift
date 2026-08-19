import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// The two official host downstream streams. The endpoint names map directly to
/// `toFetchHandler`: GET `/api/events.mux` and GET `/api/events.host`.
enum DSHSSEEndpoint: String, Sendable {
    case mux = "api/events.mux"
    case host = "api/events.host"
}

/// Deterministic reconnect policy for a live Host downstream stream. A nil retry
/// limit is deliberate: a verified Host may be restarting while the native shell
/// remains resident. Caller cancellation is always final regardless of this limit.
struct SSEReconnectPolicy: Equatable, Sendable {
    let initialDelay: TimeInterval
    let maximumDelay: TimeInterval
    let multiplier: Double
    let maximumReconnectAttempts: Int?

    init(
        initialDelay: TimeInterval = 0.25,
        maximumDelay: TimeInterval = 8,
        multiplier: Double = 2,
        maximumReconnectAttempts: Int? = nil
    ) {
        self.initialDelay = max(0, initialDelay)
        self.maximumDelay = max(self.initialDelay, maximumDelay)
        self.multiplier = max(1, multiplier)
        self.maximumReconnectAttempts = maximumReconnectAttempts
    }

    func delay(forReconnectAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return min(maximumDelay, initialDelay * pow(multiplier, Double(attempt - 1)))
    }
}

/// Payload-free observation of reconnect behavior. Diagnostics can record this
/// fact without retaining SSE body contents or settings/session material.
struct SSEReconnectTrace: Equatable, Sendable {
    enum Outcome: String, Equatable, Sendable {
        case opened
        case reconnecting
        case finished
        case cancelled
        case exhausted
    }

    let endpoint: DSHSSEEndpoint
    let attempt: Int
    let outcome: Outcome
    let errorCategory: String?
}

typealias SSEFrameStream = AsyncThrowingStream<RPCServerRequest, Error>

/// Native parser for the official SSE carrier. It mirrors the locked TypeScript
/// fetch carrier: `data:` chunks form one ServerRequest frame at a blank line;
/// malformed or unexpected envelope frames are dropped rather than terminating a
/// healthy stream. Reconnection owns a layer above one physical connection.
actor SSEClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let testStreamOpener: (@Sendable (DSHSSEEndpoint) -> SSEFrameStream)?
    private var reconnectTraces: [SSEReconnectTrace] = []

    init(
        baseURL: URL,
        session: URLSession = .shared,
        testStreamOpener: (@Sendable (DSHSSEEndpoint) -> SSEFrameStream)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.testStreamOpener = testStreamOpener
    }

    /// One physical downstream connection. The fixed rc.7 Host registers its
    /// live `events.mux` and `events.host` routes as WebSocket upgrades; its
    /// pure fetch handler exposes SSE only for in-process use. Most clients
    /// should use `reconnectingStream` rather than this physical stream.
    func stream(_ endpoint: DSHSSEEndpoint) -> SSEFrameStream {
        if let testStreamOpener { return testStreamOpener(endpoint) }
        return webSocketStream(endpoint)
    }

    /// Opens a downstream stream repeatedly after terminal connection errors or
    /// clean Host disconnects. A reconnect does not re-emit an already delivered
    /// `rpcId`, nor a lower/equal sequence for `session/event` or
    /// `session/projection`; this preserves session projection idempotency when a
    /// Host restart replays its subscription tail.
    func reconnectingStream(
        _ endpoint: DSHSSEEndpoint,
        policy: SSEReconnectPolicy = SSEReconnectPolicy()
    ) -> SSEFrameStream {
        SSEFrameStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                var retryAttempt = 0
                var fence = SSEReplayFence()
                while !Task.isCancelled {
                    await self.appendReconnectTrace(endpoint: endpoint, attempt: retryAttempt, outcome: .opened, errorCategory: nil)
                    var deliveredFrame = false
                    do {
                        let physical = await self.stream(endpoint)
                        for try await frame in physical {
                            try Task.checkCancellation()
                            deliveredFrame = true
                            if fence.accepts(frame) {
                                continuation.yield(frame)
                            }
                        }
                    } catch is CancellationError {
                        break
                    } catch let error as DSHTransportError where error == .cancelled {
                        break
                    } catch {
                        retryAttempt += 1
                        if Self.shouldExhaust(policy: policy, retryAttempt: retryAttempt) {
                            await self.appendReconnectTrace(endpoint: endpoint, attempt: retryAttempt, outcome: .exhausted, errorCategory: Self.errorCategory(error))
                            continuation.finish(throwing: error)
                            return
                        }
                        await self.appendReconnectTrace(endpoint: endpoint, attempt: retryAttempt, outcome: .reconnecting, errorCategory: Self.errorCategory(error))
                        if !(await Self.sleepBeforeReconnect(policy: policy, retryAttempt: retryAttempt)) { break }
                        continue
                    }

                    guard !Task.isCancelled else { break }
                    retryAttempt = deliveredFrame ? 1 : retryAttempt + 1
                    if Self.shouldExhaust(policy: policy, retryAttempt: retryAttempt) {
                        await self.appendReconnectTrace(endpoint: endpoint, attempt: retryAttempt, outcome: .exhausted, errorCategory: "stream-ended")
                        continuation.finish(throwing: DSHTransportError.network("SSE stream ended"))
                        return
                    }
                    await self.appendReconnectTrace(endpoint: endpoint, attempt: retryAttempt, outcome: .reconnecting, errorCategory: "stream-ended")
                    if !(await Self.sleepBeforeReconnect(policy: policy, retryAttempt: retryAttempt)) { break }
                }
                await self.appendReconnectTrace(endpoint: endpoint, attempt: retryAttempt, outcome: .cancelled, errorCategory: nil)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func recentReconnectTraces() -> [SSEReconnectTrace] {
        reconnectTraces
    }

    private func webSocketStream(_ endpoint: DSHSSEEndpoint) -> SSEFrameStream {
        SSEFrameStream { continuation in
            let socket: URLSessionWebSocketTask
            do {
                socket = try makeWebSocketTask(endpoint: endpoint)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let reader = Task {
                do {
                    socket.resume()
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        try Task.checkCancellation()
                        guard let frame = Self.decodeWebSocketFrame(message, decoder: decoder) else { continue }
                        continuation.yield(frame)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DSHTransportError.cancelled)
                } catch {
                    continuation.finish(throwing: Self.normalize(error))
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func makeWebSocketTask(endpoint: DSHSSEEndpoint) throws -> URLSessionWebSocketTask {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw DSHTransportError.invalidEndpoint
        }
        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        case "ws", "wss": break
        default: throw DSHTransportError.invalidEndpoint
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/" + endpoint.rawValue
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw DSHTransportError.invalidEndpoint }
        return session.webSocketTask(with: url)
    }

    private static func decodeWebSocketFrame(
        _ message: URLSessionWebSocketTask.Message,
        decoder: JSONDecoder
    ) -> RPCServerRequest? {
        let data: Data
        switch message {
        case let .string(value): data = Data(value.utf8)
        case let .data(value): data = value
        @unknown default: return nil
        }
        guard let frame = try? decoder.decode(RPCServerRequest.self, from: data),
              frame.type == "server-request" else {
            return nil
        }
        return frame
    }

    private static func shouldExhaust(policy: SSEReconnectPolicy, retryAttempt: Int) -> Bool {
        guard let maximum = policy.maximumReconnectAttempts else { return false }
        return retryAttempt > maximum
    }

    private static func sleepBeforeReconnect(policy: SSEReconnectPolicy, retryAttempt: Int) async -> Bool {
        let delay = policy.delay(forReconnectAttempt: retryAttempt)
        guard delay > 0 else { return !Task.isCancelled }
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func appendReconnectTrace(
        endpoint: DSHSSEEndpoint,
        attempt: Int,
        outcome: SSEReconnectTrace.Outcome,
        errorCategory: String?
    ) {
        reconnectTraces.append(SSEReconnectTrace(endpoint: endpoint, attempt: attempt, outcome: outcome, errorCategory: errorCategory))
        if reconnectTraces.count > 100 {
            reconnectTraces.removeFirst(reconnectTraces.count - 100)
        }
    }

    private static func normalize(_ error: Error) -> Error {
        if let transport = error as? DSHTransportError { return transport }
        if error is CancellationError { return DSHTransportError.cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return DSHTransportError.timeout
            case .cancelled: return DSHTransportError.cancelled
            default: return DSHTransportError.network(urlError.localizedDescription)
            }
        }
        // URLSessionWebSocketTask may report an abrupt peer close as an
        // NSPOSIXErrorDomain `Socket is not connected` rather than URLError.
        // This is a carrier outage, not an uncaught task failure or final
        // cancellation; reconnectingStream must therefore reopen it.
        return DSHTransportError.network(error.localizedDescription)
    }

    private static func errorCategory(_ error: Error) -> String {
        switch error {
        case let transport as DSHTransportError:
            switch transport {
            case .timeout: return "timeout"
            case .cancelled: return "cancelled"
            case .network: return "network"
            case .invalidHTTPStatus: return "invalid-http-status"
            case .invalidContentType: return "invalid-content-type"
            case .invalidEndpoint: return "invalid-endpoint"
            case .unexpectedEnvelope: return "unexpected-envelope"
            case .mismatchedRPCID: return "mismatched-rpc-id"
            case .duplicateRPCID: return "duplicate-rpc-id"
            case .decoding: return "decoding"
            case .unverifiedHostBuild: return "unverified-host"
            }
        default:
            return "\(String(reflecting: type(of: error)))"
        }
    }
}

/// Parser retained for locked pure-fetch fixture compatibility: incomplete or
/// unknown SSE data is ignored rather than being treated as transport-fatal.
/// The installed rc.7 `dsh web` downlink uses WebSocket frames (above).
struct SSEFrameParser {
    private let decoder: JSONDecoder
    private var dataLines: [String] = []

    init(decoder: JSONDecoder) {
        self.decoder = decoder
    }

    mutating func consume(line: String) -> RPCServerRequest? {
        if line.isEmpty { return emit() }
        guard line.hasPrefix("data:") else { return nil }
        var data = String(line.dropFirst(5))
        if data.hasPrefix(" ") { data.removeFirst() }
        dataLines.append(data)
        return nil
    }

    mutating func finish() -> RPCServerRequest? {
        emit()
    }

    private mutating func emit() -> RPCServerRequest? {
        guard !dataLines.isEmpty else { return nil }
        defer { dataLines.removeAll(keepingCapacity: true) }
        let data = Data(dataLines.joined().utf8)
        guard let frame = try? decoder.decode(RPCServerRequest.self, from: data),
              frame.type == "server-request" else {
            return nil
        }
        return frame
    }
}

/// Replay fence applied above one physical connection. Host and mux non-sequenced
/// frames are still protected by rpcId; only official payload fields with an
/// explicit sequence get monotonic low-sequence filtering across reconnects.
private struct SSEReplayFence {
    private var deliveredRPCIDs: Set<String> = []
    private var deliveredRPCIDOrder: [String] = []
    private var highestSequenceByStream: [String: Int] = [:]

    mutating func accepts(_ frame: RPCServerRequest) -> Bool {
        guard !deliveredRPCIDs.contains(frame.rpcId) else { return false }
        if let sequenceKey = sequenceKey(for: frame),
           let sequence = sequence(for: frame) {
            guard sequence > (highestSequenceByStream[sequenceKey] ?? Int.min) else { return false }
            highestSequenceByStream[sequenceKey] = sequence
        }
        deliveredRPCIDs.insert(frame.rpcId)
        deliveredRPCIDOrder.append(frame.rpcId)
        if deliveredRPCIDOrder.count > 2_048 {
            deliveredRPCIDs.remove(deliveredRPCIDOrder.removeFirst())
        }
        return true
    }

    private func sequenceKey(for frame: RPCServerRequest) -> String? {
        guard let object = frame.payload.objectValue,
              let sessionID = object["sessionId"]?.stringValue else { return nil }
        switch frame.method {
        case "session/event", "session/projection": return "\(frame.method):\(sessionID)"
        default: return nil
        }
    }

    private func sequence(for frame: RPCServerRequest) -> Int? {
        guard let object = frame.payload.objectValue else { return nil }
        switch frame.method {
        case "session/event":
            return object["event"]?.objectValue?["seq"]?.numberValue.map(Int.init)
        case "session/projection":
            return object["seq"]?.numberValue.map(Int.init)
        default:
            return nil
        }
    }
}
