import Foundation

struct HostFailure: Equatable, Sendable, LocalizedError {
    enum Kind: String, Sendable {
        case missingNodeRuntime
        case missingPayload
        case invalidBundledBaseline
        case launchFailed
        case endpointNotAnnounced
        case verificationFailed
        case terminatedBeforeReady
        case unexpectedTermination
    }

    let kind: Kind
    let message: String
    let exitStatus: Int32?
    let logPath: String

    var errorDescription: String? { message }
}
