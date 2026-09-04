import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif
/// A payload-free trace retained by the carrier to diagnose rpcId collisions,
/// response correlation and terminal transport outcomes without logging content.
struct RPCTransportTrace: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Equatable, Sendable {
        case succeeded
        case rejected
        case failed
    }

    let timestamp: Date
    let rpcId: String?
    let method: String
    let outcome: Outcome
    let detail: String?
}

/// Native URLSession implementation of the official HTTP carrier. This actor
/// owns HTTP mechanics only; feature code must go through typed API facades.
actor DSHClientTransport {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let accessPolicy: HostRPCAccessPolicy
    private let rpcIDGenerator: @Sendable () -> String
    private var inFlightRPCIDs: Set<String> = []
    private var issuedRPCIDs: Set<String> = []
    private var issuedRPCIDOrder: [String] = []
    private var callTraces: [RPCTransportTrace] = []

    init(
        baseURL: URL,
        accessPolicy: HostRPCAccessPolicy,
        session: URLSession = .shared,
        rpcIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.baseURL = baseURL
        self.accessPolicy = accessPolicy
        self.session = session
        self.rpcIDGenerator = rpcIDGenerator
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func recentCallTraces() -> [RPCTransportTrace] {
        callTraces
    }

    func call(method: String, payload: JSONValue, timeout: TimeInterval = 30) async throws -> RPCServerResponse {
        guard accessPolicy.permits(method: method) else {
            let error = DSHTransportError.unverifiedHostBuild(accessPolicy.trust.diagnosticSummary)
            appendTrace(rpcId: nil, method: method, outcome: .rejected, detail: traceDetail(for: error))
            throw error
        }
        let rpcId: String
        do {
            rpcId = try reserveRPCID()
        } catch {
            appendTrace(rpcId: nil, method: method, outcome: .rejected, detail: traceDetail(for: error))
            throw error
        }
        defer { inFlightRPCIDs.remove(rpcId) }

        do {
            let request = RPCClientRequest(rpcId: rpcId, method: method, payload: payload)
            let response = try await post(path: method, body: request, timeout: timeout)
            guard response.type == "server-response" else {
                throw DSHTransportError.unexpectedEnvelope(response.type)
            }
            guard response.rpcId == rpcId else {
                throw DSHTransportError.mismatchedRPCID(expected: rpcId, actual: response.rpcId)
            }
            appendTrace(rpcId: rpcId, method: method, outcome: .succeeded, detail: nil)
            return response
        } catch {
            appendTrace(rpcId: rpcId, method: method, outcome: .failed, detail: traceDetail(for: error))
            throw error
        }
    }

    private func reserveRPCID() throws -> String {
        let rpcId = rpcIDGenerator()
        guard !issuedRPCIDs.contains(rpcId), inFlightRPCIDs.insert(rpcId).inserted else {
            throw DSHTransportError.duplicateRPCID(rpcId)
        }
        issuedRPCIDs.insert(rpcId)
        issuedRPCIDOrder.append(rpcId)
        if issuedRPCIDOrder.count > 1_024 {
            issuedRPCIDs.remove(issuedRPCIDOrder.removeFirst())
        }
        return rpcId
    }

    private func traceDetail(for error: Error) -> String {
        switch error {
        case let business as RPCBusinessError:
            return "business-error:\(business.code)"
        case let transport as DSHTransportError:
            switch transport {
            case .duplicateRPCID: return "duplicate-rpc-id"
            case .mismatchedRPCID: return "mismatched-rpc-id"
            case .unexpectedEnvelope: return "unexpected-envelope"
            case .invalidContentType: return "invalid-content-type"
            case .invalidHTTPStatus: return "invalid-http-status"
            case .timeout: return "timeout"
            case .network: return "network"
            case .unverifiedHostBuild: return "unverified-host"
            case .cancelled: return "cancelled"
            case .invalidEndpoint: return "invalid-endpoint"
            case .decoding: return "decoding"
            }
        default:
            return "\(String(reflecting: type(of: error)))"
        }
    }

    private func appendTrace(
        rpcId: String?,
        method: String,
        outcome: RPCTransportTrace.Outcome,
        detail: String?
    ) {
        callTraces.append(RPCTransportTrace(timestamp: Date(), rpcId: rpcId, method: method, outcome: outcome, detail: detail))
        if callTraces.count > 100 {
            callTraces.removeFirst(callTraces.count - 100)
        }
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

    /// The attachment is read-only on the Host but materializes a native file,
    /// so it remains unavailable to an unverified diagnostic-only endpoint.
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
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw DSHTransportError.timeout
            case .cancelled: throw DSHTransportError.cancelled
            default: throw DSHTransportError.network(error.localizedDescription)
            }
        } catch let error as DSHTransportError {
            throw error
        } catch {
            throw DSHTransportError.network(error.localizedDescription)
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
