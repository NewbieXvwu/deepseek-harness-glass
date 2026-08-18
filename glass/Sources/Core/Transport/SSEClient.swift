import Foundation

/// The two official host downstream streams. The endpoint names map directly to
/// `toFetchHandler`: GET `/api/events.mux` and GET `/api/events.host`.
enum DSHSSEEndpoint: String, Sendable {
    case mux = "api/events.mux"
    case host = "api/events.host"
}

/// Native parser for the official SSE carrier. Reconnection policy intentionally
/// lives above this type so ownership and retry state remain in Host/Session.
actor SSEClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    func stream(_ endpoint: DSHSSEEndpoint) -> AsyncThrowingStream<RPCServerRequest, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await read(endpoint: endpoint, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DSHTransportError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func read(
        endpoint: DSHSSEEndpoint,
        continuation: AsyncThrowingStream<RPCServerRequest, Error>.Continuation
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

        var dataLines: [String] = []
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty {
                try emit(dataLines: &dataLines, continuation: continuation)
                continue
            }
            if line.hasPrefix("data:") {
                var data = String(line.dropFirst(5))
                if data.hasPrefix(" ") { data.removeFirst() }
                dataLines.append(data)
            }
            // `event`, `id`, `retry`, comments and unknown fields are transport
            // metadata; official payload identity remains inside the JSON envelope.
        }
        try emit(dataLines: &dataLines, continuation: continuation)
    }

    private func emit(
        dataLines: inout [String],
        continuation: AsyncThrowingStream<RPCServerRequest, Error>.Continuation
    ) throws {
        guard !dataLines.isEmpty else { return }
        defer { dataLines.removeAll(keepingCapacity: true) }
        let data = Data(dataLines.joined(separator: "\n").utf8)
        let frame: RPCServerRequest
        do {
            frame = try decoder.decode(RPCServerRequest.self, from: data)
        } catch {
            throw DSHTransportError.decoding(error.localizedDescription)
        }
        guard frame.type == "server-request" else {
            throw DSHTransportError.unexpectedEnvelope(frame.type)
        }
        continuation.yield(frame)
    }
}
