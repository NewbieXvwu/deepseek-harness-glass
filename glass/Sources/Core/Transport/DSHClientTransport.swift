import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif
/// Native URLSession implementation of the official HTTP carrier. This actor
/// owns HTTP mechanics only; feature code must go through typed API facades.
actor DSHClientTransport {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func call(method: String, payload: JSONValue, timeout: TimeInterval = 30) async throws -> RPCServerResponse {
        let rpcId = UUID().uuidString.lowercased()
        let request = RPCClientRequest(rpcId: rpcId, method: method, payload: payload)
        let response = try await post(path: method, body: request, timeout: timeout)
        guard response.type == "server-response" else {
            throw DSHTransportError.unexpectedEnvelope(response.type)
        }
        guard response.rpcId == rpcId else {
            throw DSHTransportError.mismatchedRPCID(expected: rpcId, actual: response.rpcId)
        }
        return response
    }

    func respond(_ response: RPCClientResponse, timeout: TimeInterval = 30) async throws -> RPCReceipt {
        var request = try makeRequest(path: "respond", timeout: timeout)
        request.httpBody = try encoder.encode(response)
        let (data, http) = try await perform(request)
        try validateJSONResponse(http, data: data)
        do {
            return try decoder.decode(RPCReceipt.self, from: data)
        } catch {
            throw DSHTransportError.decoding(error.localizedDescription)
        }
    }

    func downloadURL(sessionID: String, includeDescendants: Bool = true) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/session.export"), resolvingAgainstBaseURL: false) else {
            throw DSHTransportError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionID),
            URLQueryItem(name: "includeDescendants", value: includeDescendants ? "true" : "false"),
        ]
        guard let url = components.url else { throw DSHTransportError.invalidEndpoint }
        return url
    }

    private func post<T: Encodable>(path: String, body: T, timeout: TimeInterval) async throws -> RPCServerResponse {
        var request = try makeRequest(path: path, timeout: timeout)
        request.httpBody = try encoder.encode(body)
        let (data, http) = try await perform(request)
        try validateJSONResponse(http, data: data)
        do {
            return try decoder.decode(RPCServerResponse.self, from: data)
        } catch {
            throw DSHTransportError.decoding(error.localizedDescription)
        }
    }

    private func makeRequest(path: String, timeout: TimeInterval) throws -> URLRequest {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: "api/\(relative)", relativeTo: baseURL) else {
            throw DSHTransportError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DSHTransportError.invalidEndpoint
            }
            guard (200 ... 299).contains(http.statusCode) else {
                throw DSHTransportError.invalidHTTPStatus(
                    http.statusCode,
                    body: String(decoding: data, as: UTF8.self)
                )
            }
            return (data, http)
        } catch is CancellationError {
            throw DSHTransportError.cancelled
        } catch let error as DSHTransportError {
            throw error
        } catch {
            throw DSHTransportError.decoding(error.localizedDescription)
        }
    }

    private func validateJSONResponse(_ response: HTTPURLResponse, data: Data) throws {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased()
        guard contentType?.contains("application/json") == true else {
            // The official carrier deliberately uses non-JSON text for 404/415/
            // malformed carrier errors. A successful unary API call must be JSON.
            throw DSHTransportError.invalidContentType(contentType)
        }
        guard !data.isEmpty else {
            throw DSHTransportError.decoding("empty JSON response")
        }
    }
}
