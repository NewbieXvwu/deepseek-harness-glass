import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum RemoteMuxConnectionError: Error, Sendable, Equatable {
    case carrierLost(String)
    case protocolViolation(String)
}

actor RemoteMuxConnection {
    private struct Sink: Sendable {
        let yield: @Sendable (RemoteJSONValue?) -> Void
        let finish: @Sendable (Error?) -> Void
    }

    private struct OpenMessage<Arguments: Encodable>: Encodable {
        let type = "open"
        let streamId: String
        let endpoint: String
        let payload: Payload
        struct Payload: Encodable { let args: Arguments }
    }

    private struct CancelMessage: Encodable {
        let type = "cancel"
        let streamId: String
    }

    private struct ServerMessage: Decodable {
        let type: String
        let streamId: String
        let value: RemoteJSONValue?
        let error: RemoteFailurePayload?
    }

    private let authenticatedHost: AuthenticatedHostSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sinks: [String: Sink] = [:]
    private var closed = false

    init(authenticatedHost: AuthenticatedHostSession) {
        self.authenticatedHost = authenticatedHost
    }

    func open<Arguments, Frame>(
        _ procedure: RemoteStreamProcedure<Arguments, Frame>,
        arguments: Arguments
    ) async throws -> AsyncThrowingStream<Frame, Error>
    where Arguments: Encodable & Sendable, Frame: Decodable & Sendable {
        guard !closed else { throw RemoteMuxConnectionError.carrierLost("Remote mux is closed") }
        let socket = startSocketIfNeeded()
        let streamID = UUID().uuidString.lowercased()
        let pair = AsyncThrowingStream<Frame, Error>.makeStream()
        let continuation = pair.continuation
        let sink = Sink(
            yield: { value in
                do {
                    guard let value else {
                        throw RemoteMuxConnectionError.protocolViolation("Remote stream item omitted value")
                    }
                    let data = try JSONEncoder().encode(value)
                    continuation.yield(try JSONDecoder().decode(Frame.self, from: data))
                } catch {
                    continuation.finish(throwing: error)
                }
            },
            finish: { error in
                if let error { continuation.finish(throwing: error) }
                else { continuation.finish() }
            }
        )
        sinks[streamID] = sink
        continuation.onTermination = { @Sendable [weak self] _ in
            guard let self else { return }
            Task { await self.cancel(streamID: streamID) }
        }

        do {
            let message = OpenMessage(
                streamId: streamID,
                endpoint: procedure.endpoint,
                payload: .init(args: arguments)
            )
            try await send(message, on: socket)
        } catch {
            sinks.removeValue(forKey: streamID)
            continuation.finish(throwing: error)
            throw error
        }
        return pair.stream
    }

    func close() async {
        guard !closed else { return }
        closed = true
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        failAll(RemoteMuxConnectionError.carrierLost("Remote mux closed"))
    }

    private func startSocketIfNeeded() -> URLSessionWebSocketTask {
        if let socket { return socket }
        var components = URLComponents(url: authenticatedHost.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/remote.mux"
        components.query = nil
        components.fragment = nil
        let created = authenticatedHost.urlSession.webSocketTask(with: components.url!)
        socket = created
        created.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop(created) }
        return created
    }

    private func receiveLoop(_ source: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await source.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default:
                    throw RemoteMuxConnectionError.protocolViolation("unsupported WebSocket message")
                }
                let frame = try JSONDecoder().decode(ServerMessage.self, from: data)
                guard let sink = sinks[frame.streamId] else { continue }
                switch frame.type {
                case "item": sink.yield(frame.value)
                case "end":
                    sinks.removeValue(forKey: frame.streamId)
                    sink.finish(nil)
                case "error":
                    sinks.removeValue(forKey: frame.streamId)
                    guard let error = frame.error else {
                        sink.finish(RemoteMuxConnectionError.protocolViolation("Remote stream error omitted payload"))
                        continue
                    }
                    sink.finish(RemoteConnectionError.remote(error))
                default:
                    throw RemoteMuxConnectionError.protocolViolation("unknown Remote stream frame \(frame.type)")
                }
            }
        } catch {
            if socket === source { socket = nil }
            if !closed && !Task.isCancelled {
                failAll(RemoteMuxConnectionError.carrierLost(String(describing: error)))
            }
        }
    }

    private func cancel(streamID: String) async {
        guard sinks.removeValue(forKey: streamID) != nil,
              let socket,
              !closed
        else { return }
        try? await send(CancelMessage(streamId: streamID), on: socket)
    }

    private func send<Message: Encodable>(_ message: Message, on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RemoteMuxConnectionError.protocolViolation("failed to encode Remote stream message")
        }
        do {
            try await socket.send(.string(text))
        } catch {
            throw RemoteMuxConnectionError.carrierLost(String(describing: error))
        }
    }

    private func failAll(_ error: Error) {
        let active = sinks.values
        sinks.removeAll()
        for sink in active { sink.finish(error) }
    }
}
