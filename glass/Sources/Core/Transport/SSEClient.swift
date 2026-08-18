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

    /// One physical SSE connection. Most clients should use `reconnectingStream`.
    func stream(_ endpoint: DSHSSEEndpoint) -> SSEFrameStream {
        if let testStreamOpener { return testStreamOpener(endpoint) }
        return physicalStream(endpoint)
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

    private func physicalStream(_ endpoint: DSHSSEEndpoint) -> SSEFrameStream {
        SSEFrameStream { continuation in
            let task = Task {
                do {
                    try await read(endpoint: endpoint, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DSHTransportError.cancelled)
                } catch {
                    continuation.finish(throwing: Self.normalize(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func read(
        endpoint: DSHSSEEndpoint,
        continuation: SSEFrameStream.Continuation
    ) async throws {
        guard let url = URL(string: endpoint.rawValue, relativeTo: baseURL) else {
            throw DSHTransportError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 0

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DSHTransportError.invalidEndpoint }
        guard (200 ... 299).contains(http.statusCode) else {
            throw DSHTransportError.invalidHTTPStatus(http.statusCode, body: "SSE connection refused")
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
            throw DSHTransportError.invalidContentType(http.value(forHTTPHeaderField: "Content-Type"))
        }

        var parser = SSEFrameParser(decoder: decoder)
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let frame = parser.consume(line: line) {
                continuation.yield(frame)
            }
        }
        if let frame = parser.finish() {
            continuation.yield(frame)
        }
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
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .timedOut: return DSHTransportError.timeout
        case .cancelled: return DSHTransportError.cancelled
        default: return DSHTransportError.network(urlError.localizedDescription)
        }
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

/// Mirrors official `readSse`: incomplete/unknown data is ignored, not treated
/// as a transport-fatal error. The physical connection remains consumable after
/// one malformed ServerRequest frame.
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
