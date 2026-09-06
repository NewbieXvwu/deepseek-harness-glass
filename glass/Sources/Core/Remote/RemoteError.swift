import Foundation

enum RemoteFailureCategory: String, Sendable, Equatable {
    case authentication
    case transport
    case carrierLost
    case remoteBusiness
    case methodUnavailable
    case protocolViolation
}

enum RemoteConnectionError: Error, Sendable, Equatable {
    case authenticationRequired
    case httpStatus(Int)
    case transport(String)
    case carrierLost(String)
    case correlationMismatch(expected: String, actual: String)
    case protocolViolation(String)
    case remote(RemoteFailurePayload)

    var category: RemoteFailureCategory {
        switch self {
        case .authenticationRequired:
            return .authentication
        case .httpStatus(404):
            return .methodUnavailable
        case .httpStatus, .transport:
            return .transport
        case .carrierLost:
            return .carrierLost
        case .correlationMismatch, .protocolViolation:
            return .protocolViolation
        case let .remote(failure):
            return Self.methodUnavailableCodes.contains(failure.code) ? .methodUnavailable : .remoteBusiness
        }
    }

    private static let methodUnavailableCodes: Set<String> = [
        "gateway/definition-unavailable",
        "gateway/invocation-unavailable",
        "gateway/method-unavailable",
    ]
}
