import Foundation

enum RemoteConnectionError: Error, Sendable, Equatable {
    case authenticationRequired
    case httpStatus(Int)
    case transport(String)
    case correlationMismatch(expected: String, actual: String)
    case protocolViolation(String)
    case remote(RemoteFailurePayload)
}
