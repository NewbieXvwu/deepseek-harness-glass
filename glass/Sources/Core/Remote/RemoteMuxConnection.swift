import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


actor RemoteMuxConnection {
    private struct Sink: Sendable {
        let yield: @Sendable (Data) throws -> Void
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

    private struct DynamicKey: CodingKey, Equatable {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }

        static let type = DynamicKey(stringValue: "type")
        static let streamId = DynamicKey(stringValue: "streamId")
        static let error = DynamicKey(stringValue: "error")
    }

    private struct ServerEnvelope: Decodable {
        let type: String
        let streamId: String
        let failure: RemoteFailurePayload?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            let streamID = try container.decode(String.self, forKey: .streamId)
            guard !streamID.isEmpty else {
                throw RemoteConnectionError.protocolViolation("Remote stream frame has empty streamId")
            }
            let frameType = try container.decode(String.self, forKey: .type)
            self.type = frameType
            self.streamId = streamID
            // Unknown or extra keys are tolerated so an additive Host field can
            // never tear down the whole multiplexed carrier.
            switch frameType {
            case "error":
                failure = try? container.decode(RemoteFailurePayload.self, forKey: .error)
            default:
                failure = nil
            }
        }
    }

    private struct ItemEnvelope<Frame: Decodable>: Decodable {
        let value: Frame?
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    private let authenticatedHost: AuthenticatedHostSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sinks: [String: Sink] = [:]
    private var closed = false

    init(authenticatedHost: AuthenticatedHostSession) {
        self.authenticatedHost = authenticatedHost
    }

    static func decodeItem<Frame: Decodable>(_ type: Frame.Type, data: Data) throws -> Frame {
        do {
            let item = try decoder.decode(ItemEnvelope<Frame>.self, from: data)
            guard let value = item.value else {
                throw RemoteConnectionError.protocolViolation("Remote stream item omitted value")
            }
            return value
        } catch let error as RemoteConnectionError {
            throw error
        } catch {
            throw RemoteConnectionError.protocolViolation("invalid Remote stream item value: \(error)")
        }
    }

    static func encodeMessage<Message: Encodable>(_ message: Message) throws -> String {
        do {
            let data = try encoder.encode(message)
            guard let text = String(data: data, encoding: .utf8) else {
                throw RemoteConnectionError.protocolViolation("failed to encode Remote stream message")
            }
            return text
        } catch let error as RemoteConnectionError {
            throw error
        } catch {
            throw RemoteConnectionError.protocolViolation("failed to encode Remote stream message: \(error)")
        }
    }

    func open<Arguments, Frame>(
        _ procedure: RemoteStreamProcedure<Arguments, Frame>,
        arguments: Arguments
    ) async throws -> AsyncThrowingStream<Frame, Error>
    where Arguments: Encodable & Sendable, Frame: Decodable & Sendable {
        guard !closed else { throw RemoteConnectionError.carrierLost("Remote mux is closed") }
        let socket = try startSocketIfNeeded()
        let streamID = UUID().uuidString.lowercased()
        let pair = AsyncThrowingStream<Frame, Error>.makeStream()
        let continuation = pair.continuation
        let sink = Sink(
            yield: { data in
                continuation.yield(try Self.decodeItem(Frame.self, data: data))
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
                endpoint: procedure.endpoint.rawValue,
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
        failAll(RemoteConnectionError.carrierLost("Remote mux closed"))
    }

    private func startSocketIfNeeded() throws -> URLSessionWebSocketTask {
        if let socket { return socket }
        guard var components = URLComponents(url: authenticatedHost.baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteConnectionError.protocolViolation("invalid authenticated Host URL")
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/remote.mux"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw RemoteConnectionError.protocolViolation("invalid Remote mux URL")
        }
        let created = authenticatedHost.urlSession.webSocketTask(with: url)
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
                case .data:
                    throw RemoteConnectionError.protocolViolation("Remote stream WebSocket requires text messages")
                case let .string(value):
                    data = Data(value.utf8)
                @unknown default:
                    throw RemoteConnectionError.protocolViolation("unsupported WebSocket message")
                }
                let frame: ServerEnvelope
                do {
                    frame = try Self.decoder.decode(ServerEnvelope.self, from: data)
                } catch let error as RemoteConnectionError {
                    throw error
                } catch {
                    throw RemoteConnectionError.protocolViolation("invalid Remote stream server message: \(error)")
                }
                guard let sink = sinks[frame.streamId] else { continue }
                switch frame.type {
                case "item":
                    // A malformed item payload fails only its own logical stream;
                    // the carrier and every sibling stream stay usable.
                    do {
                        try sink.yield(data)
                    } catch {
                        sinks.removeValue(forKey: frame.streamId)
                        sink.finish(error)
                    }
                case "end":
                    sinks.removeValue(forKey: frame.streamId)
                    sink.finish(nil)
                case "error":
                    sinks.removeValue(forKey: frame.streamId)
                    guard let error = frame.failure else {
                        sink.finish(RemoteConnectionError.protocolViolation("Remote stream error omitted payload"))
                        continue
                    }
                    sink.finish(RemoteConnectionError.remote(error))
                default:
                    // Unknown additive frame: ignore it without disturbing any stream.
                    continue
                }
            }
        } catch {
            if socket === source { socket = nil }
            guard !closed, !Task.isCancelled else { return }
            if let remoteError = error as? RemoteConnectionError,
               remoteError.category == .protocolViolation {
                source.cancel(with: .protocolError, reason: nil)
                failAll(remoteError)
            } else {
                failAll(RemoteConnectionError.carrierLost(String(describing: error)))
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
        let text = try Self.encodeMessage(message)
        do {
            try await socket.send(.string(text))
        } catch {
            throw RemoteConnectionError.carrierLost(String(describing: error))
        }
    }

    private func failAll(_ error: Error) {
        let active = sinks.values
        sinks.removeAll()
        for sink in active { sink.finish(error) }
    }
}
