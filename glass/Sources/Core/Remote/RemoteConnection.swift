import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RemoteConnection: Sendable {
    let authenticatedHost: AuthenticatedHostSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let mux: RemoteMuxConnection
    private let generations: RemoteGenerationCounter

    init(authenticatedHost: AuthenticatedHostSession) {
        self.authenticatedHost = authenticatedHost
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.mux = RemoteMuxConnection(authenticatedHost: authenticatedHost)
        self.generations = RemoteGenerationCounter()
    }

    func call<Arguments, Output>(
        _ procedure: RemoteProcedure<Arguments, Output>,
        arguments: Arguments
    ) async throws -> Output where Arguments: Encodable & Sendable, Output: Decodable & Sendable {
        let rpcID = UUID().uuidString.lowercased()
        let body: Data
        do {
            body = try RemoteWireCodec.request(
                rpcID: rpcID,
                endpoint: procedure.endpoint,
                arguments: arguments,
                encoder: encoder
            )
        } catch {
            throw RemoteConnectionError.protocolViolation("failed to encode \(procedure.endpoint): \(error)")
        }

        let url = authenticatedHost.baseURL.appending(path: "api").appending(path: procedure.endpoint)
        var request = URLRequest(url: url, timeoutInterval: procedure.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await authenticatedHost.urlSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RemoteConnectionError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteConnectionError.protocolViolation("non-HTTP Remote response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw RemoteConnectionError.authenticationRequired
        }
        guard http.statusCode == 200 else {
            throw RemoteConnectionError.httpStatus(http.statusCode)
        }

        let decoded: (rpcID: String, result: RemoteDecodedResult<Output>)
        do {
            decoded = try RemoteWireCodec.response(Output.self, data: data, decoder: decoder)
        } catch let error as RemoteConnectionError {
            throw error
        } catch {
            throw RemoteConnectionError.protocolViolation("failed to decode \(procedure.endpoint): \(error)")
        }
        guard decoded.rpcID == rpcID else {
            throw RemoteConnectionError.correlationMismatch(expected: rpcID, actual: decoded.rpcID)
        }
        switch decoded.result {
        case let .value(value): return value
        case let .failure(error): throw RemoteConnectionError.remote(error)
        }
    }
    func callNoValue<Arguments: Encodable & Sendable>(
        endpoint: String,
        arguments: Arguments,
        timeout: TimeInterval = 30
    ) async throws {
        let rpcID = UUID().uuidString.lowercased()
        let body: Data
        do {
            body = try RemoteWireCodec.request(
                rpcID: rpcID,
                endpoint: endpoint,
                arguments: arguments,
                encoder: encoder
            )
        } catch {
            throw RemoteConnectionError.protocolViolation("failed to encode \(endpoint): \(error)")
        }

        let url = authenticatedHost.baseURL.appending(path: "api").appending(path: endpoint)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await authenticatedHost.urlSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RemoteConnectionError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteConnectionError.protocolViolation("non-HTTP Remote response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw RemoteConnectionError.authenticationRequired
        }
        guard http.statusCode == 200 else {
            throw RemoteConnectionError.httpStatus(http.statusCode)
        }

        let decoded: (rpcID: String, result: RemoteDecodedNoValue)
        do {
            decoded = try RemoteWireCodec.responseNoValue(data: data, decoder: decoder)
        } catch let error as RemoteConnectionError {
            throw error
        } catch {
            throw RemoteConnectionError.protocolViolation("failed to decode \(endpoint): \(error)")
        }
        guard decoded.rpcID == rpcID else {
            throw RemoteConnectionError.correlationMismatch(expected: rpcID, actual: decoded.rpcID)
        }
        if case let .failure(error) = decoded.result {
            throw RemoteConnectionError.remote(error)
        }
    }

    func stream<Arguments, Frame>(
        _ procedure: RemoteStreamProcedure<Arguments, Frame>,
        arguments: Arguments
    ) async throws -> AsyncThrowingStream<Frame, Error>
    where Arguments: Encodable & Sendable, Frame: Decodable & Sendable {
        try await mux.open(procedure, arguments: arguments)
    }

    func connectEvents() async throws -> RemoteEventChannel {
        struct EmptyArguments: Codable, Sendable {}
        let source: AsyncThrowingStream<RemoteEventDownlinkFrame, Error> = try await stream(
            RemoteStreamProcedure("$events"),
            arguments: EmptyArguments()
        )
        var iterator = source.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw RemoteMuxConnectionError.protocolViolation("$events ended before ready")
        }
        guard case let .ready(ready) = first else {
            throw RemoteMuxConnectionError.protocolViolation("$events did not begin with ready")
        }
        let generation = await generations.next()
        let pair = AsyncThrowingStream<RemoteEventDownlinkFrame, Error>.makeStream()
        Task {
            do {
                while let frame = try await iterator.next() {
                    if case .ready = frame {
                        throw RemoteMuxConnectionError.protocolViolation("$events emitted a second ready frame")
                    }
                    pair.continuation.yield(frame)
                }
                pair.continuation.finish()
            } catch {
                pair.continuation.finish(throwing: error)
            }
        }
        return .init(generation: generation, ready: ready, events: pair.stream)
    }

    func closeStreams() async {
        await mux.close()
    }

}
