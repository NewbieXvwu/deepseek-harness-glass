import Foundation

/// JSON-safe value used at the transport and projection boundaries. It is the
/// same type as `RemoteJSONValue`; the alias keeps the legacy call sites honest
/// without a second recursive value type.
typealias JSONValue = RemoteJSONValue

/// Mirrors the official closed business-error branch. `details` is deliberately
/// retained as JSON because the typed error detail depends on the RPC method.
struct RPCBusinessError: Codable, Equatable, Sendable, Error {
    let code: String
    let message: String
    let details: JSONValue
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
    case cancelled

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
        case .cancelled: return "DeepSeek Harness request was cancelled."
        }
    }
}
