import Foundation

/// JSON-safe value used only at the transport boundary. Feature modules must
/// decode from this value through typed DTO adapters rather than handling raw
/// dictionaries or URL payloads directly.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }
}

/// Matches the official `ClientRequest` wire form sent as POST `/api/<method>`.
struct RPCClientRequest: Codable, Equatable, Sendable {
    let type: String
    let rpcId: String
    let method: String
    let payload: JSONValue

    init(rpcId: String, method: String, payload: JSONValue) {
        self.type = "client-request"
        self.rpcId = rpcId
        self.method = method
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey { case type, rpcId, method, payload }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "client-request" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected client-request envelope")
        }
        self.type = type
        self.rpcId = try container.decode(String.self, forKey: .rpcId)
        self.method = try container.decode(String.self, forKey: .method)
        self.payload = try container.decode(JSONValue.self, forKey: .payload)
    }
}

/// Mirrors the official closed business-error branch. `details` is deliberately
/// retained as JSON because the typed error detail depends on the RPC method.
struct RPCBusinessError: Codable, Equatable, Sendable, Error {
    let code: String
    let message: String
    let details: JSONValue

    var disposition: RPCErrorDisposition {
        let normalized = code.lowercased()
        if normalized.contains("revision") || normalized.contains("conflict") || normalized.contains("stale") {
            return .requiresRefresh
        }
        if normalized.contains("invalid") || normalized.contains("validation") || normalized.contains("required") || normalized.contains("permission") {
            return .requiresUserCorrection
        }
        if normalized.contains("unsupported") || normalized.contains("not_found") || normalized.contains("notfound") || normalized.contains("method") {
            return .unsupported
        }
        if normalized.contains("retry") || normalized.contains("busy") || normalized.contains("unavailable") || normalized.contains("rate") {
            return .retryable
        }
        return .programFault
    }
}

/// Upper-layer decision after any official RPC or carrier failure. The mapping
/// is intentionally independent of localized error text and may be displayed or
/// retried by feature facades without inspecting transport internals.
enum RPCErrorDisposition: String, Codable, Equatable, Sendable {
    case retryable
    case requiresRefresh
    case requiresUserCorrection
    case unsupported
    case programFault
}

/// Source: `packages/client/connection/src/rpc.ts`; a type-erased envelope
/// family for fixture and transport tests. Concrete request/response structs
/// remain the wire encoders used by `DSHClientTransport`.
enum RPCEnvelope: Equatable, Sendable {
    case clientRequest(RPCClientRequest)
    case serverResponse(RPCServerResponse)
    case serverRequest(RPCServerRequest)
    case clientResponse(RPCClientResponse)
}

/// Mirrors official `RpcResult<T>`. HTTP status is transport-only; a server
/// response may be HTTP 200 while this result is a business failure.
enum RPCResult: Codable, Equatable, Sendable {
    case success(JSONValue)
    case failure(RPCBusinessError)

    private enum CodingKeys: String, CodingKey { case ok, value, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .ok) {
            self = .success(try container.decode(JSONValue.self, forKey: .value))
        } else {
            self = .failure(try container.decode(RPCBusinessError.self, forKey: .error))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .success(value):
            try container.encode(true, forKey: .ok)
            try container.encode(value, forKey: .value)
        case let .failure(error):
            try container.encode(false, forKey: .ok)
            try container.encode(error, forKey: .error)
        }
    }
}

/// Matches official `ServerResponse`; its rpcId must echo the client request.
struct RPCServerResponse: Codable, Equatable, Sendable {
    let type: String
    let rpcId: String
    let result: RPCResult
}

/// Matches official downstream SSE `ServerRequest` frames.
struct RPCServerRequest: Codable, Equatable, Sendable {
    let type: String
    let rpcId: String
    let method: String
    let payload: JSONValue
}

/// Matches official `ClientResponse` sent to POST `/api/respond`.
struct RPCClientResponse: Codable, Equatable, Sendable {
    let type: String
    let rpcId: String
    let result: RPCResult

    init(rpcId: String, result: RPCResult) {
        self.type = "client-response"
        self.rpcId = rpcId
        self.result = result
    }

    private enum CodingKeys: String, CodingKey { case type, rpcId, result }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "client-response" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected client-response envelope")
        }
        self.type = type
        self.rpcId = try container.decode(String.self, forKey: .rpcId)
        self.result = try container.decode(RPCResult.self, forKey: .result)
    }
}

struct RPCReceipt: Codable, Equatable, Sendable {
    let accepted: Bool
    let reason: String?
}

enum DSHTransportError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case invalidHTTPStatus(Int, body: String)
    case unexpectedEnvelope(String)
    case mismatchedRPCID(expected: String, actual: String)
    case duplicateRPCID(String)
    case invalidContentType(String?)
    case decoding(String)
    case timeout
    case network(String)
    case unverifiedHostBuild(String)
    case cancelled

    var disposition: RPCErrorDisposition {
        switch self {
        case .timeout, .network: return .retryable
        case let .invalidHTTPStatus(status, _):
            return (status == 408 || status == 425 || status == 429 || status >= 500) ? .retryable : .programFault
        case .unverifiedHostBuild: return .unsupported
        case .cancelled: return .requiresUserCorrection
        case .invalidEndpoint, .unexpectedEnvelope, .mismatchedRPCID, .duplicateRPCID, .invalidContentType, .decoding:
            return .programFault
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Invalid DeepSeek Harness endpoint."
        case let .invalidHTTPStatus(status, body): return "DeepSeek Harness returned HTTP \(status): \(body)"
        case let .unexpectedEnvelope(type): return "Unexpected DeepSeek Harness envelope: \(type)"
        case let .mismatchedRPCID(expected, actual): return "Mismatched RPC response id: expected \(expected), got \(actual)."
        case let .duplicateRPCID(rpcId): return "Duplicate in-flight or recently issued DeepSeek Harness rpcId: \(rpcId)."
        case let .invalidContentType(value): return "Unexpected DeepSeek Harness content type: \(value ?? "missing")."
        case let .decoding(message): return "Could not decode DeepSeek Harness response: \(message)"
        case .timeout: return "DeepSeek Harness request timed out."
        case let .network(message): return "DeepSeek Harness network request failed: \(message)"
        case let .unverifiedHostBuild(reason): return "DeepSeek Harness build is unverified; write operation is blocked: \(reason)"
        case .cancelled: return "DeepSeek Harness request was cancelled."
        }
    }
}
