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

/// Mirrors the official closed business-error branch. `details` is deliberately
/// retained as JSON because the typed error detail depends on the RPC method.
struct RPCBusinessError: Codable, Equatable, Sendable, Error {
    let code: String
    let message: String
    let details: JSONValue

    var disposition: RPCErrorDisposition {
        let normalized = code.lowercased()
        switch normalized {
        case "revision_conflict", "revision-conflict", "conflict", "stale", "stale_revision", "stale-revision":
            return .requiresRefresh
        case "validation_invalid", "validation_error", "validation-error", "invalid_argument", "invalid-argument", "invalid_request", "invalid-request", "permission_denied", "permission-denied":
            return .requiresUserCorrection
        case "method_not_found", "method-not-found", "session-not-found", "session_not_found", "workspace-not-found", "workspace_not_found", "not_found", "not-found", "notfound", "unsupported":
            return .unsupported
        case "service_unavailable", "service-unavailable", "rate_limit", "rate-limit", "busy", "unavailable", "retry":
            return .retryable
        case "internal_error", "internal-error", "internal":
            return .programFault
        default:
            break
        }
        if normalized.hasPrefix("revision") || normalized.hasPrefix("conflict") || normalized.hasPrefix("stale") {
            return .requiresRefresh
        }
        if normalized.hasPrefix("invalid") || normalized.hasPrefix("validation") || normalized.hasPrefix("required") || normalized.hasPrefix("permission") {
            return .requiresUserCorrection
        }
        if normalized.hasPrefix("unsupported") || normalized.hasPrefix("not_found") || normalized.hasPrefix("not-found") || normalized.hasPrefix("notfound") || normalized.hasPrefix("method") {
            return .unsupported
        }
        if normalized.hasPrefix("retry") || normalized.hasPrefix("busy") || normalized.hasPrefix("unavailable") || normalized.hasPrefix("rate") {
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

/// Legacy test seam for direct session mux injection. Production session streams
/// decode through `RemoteEventDownlinkFrame` and typed follow/control frames.
struct RPCServerRequest: Codable, Equatable, Sendable {
    let type: String
    let rpcId: String
    let method: String
    let payload: JSONValue
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
