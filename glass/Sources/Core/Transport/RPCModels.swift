import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif
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
}

/// Matches the official `ClientRequest` wire form sent as POST `/api/<method>`.
struct RPCClientRequest: Encodable, Sendable {
    let type = "client-request"
    let rpcId: String
    let method: String
    let payload: JSONValue
}

/// Mirrors the official closed business-error branch. `details` is deliberately
/// retained as JSON because the typed error detail depends on the RPC method.
struct RPCBusinessError: Codable, Equatable, Sendable, Error {
    let code: String
    let message: String
    let details: JSONValue
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
struct RPCClientResponse: Encodable, Sendable {
    let type = "client-response"
    let rpcId: String
    let result: RPCResult
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
    case invalidContentType(String?)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Invalid DeepSeek Harness endpoint."
        case let .invalidHTTPStatus(status, body): return "DeepSeek Harness returned HTTP \(status): \(body)"
        case let .unexpectedEnvelope(type): return "Unexpected DeepSeek Harness envelope: \(type)"
        case let .mismatchedRPCID(expected, actual): return "Mismatched RPC response id: expected \(expected), got \(actual)."
        case let .invalidContentType(value): return "Unexpected DeepSeek Harness content type: \(value ?? "missing")."
        case let .decoding(message): return "Could not decode DeepSeek Harness response: \(message)"
        case .cancelled: return "DeepSeek Harness request was cancelled."
        }
    }
}
