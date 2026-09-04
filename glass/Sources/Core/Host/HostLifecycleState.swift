import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif
/// Explicit native ownership states for the bundled DeepSeek Harness Host.
/// A URL is data carried by `.ready`, never a substitute for lifecycle state.
enum HostLifecycleState: Equatable, Sendable {
    case idle
    case probingExternal(URL?)
    case unverified(HostUnverified)
    case startingOwned
    case verifying(URL)
    case ready(HostConnection)
    case recovering(attempt: Int)
    case failed(HostFailure)
    case stopping

    var endpoint: URL? {
        switch self {
        case let .probingExternal(url): return url
        case let .verifying(url): return url
        case let .ready(connection): return connection.endpoint
        default: return nil
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}


enum HostCompatibility: Equatable, Sendable {
    case verified
    case bestEffort(reason: String)
}

struct HostConnectionContext: Sendable {
    let authenticatedHost: AuthenticatedHostSession
    let remote: RemoteConnection
    let events: RemoteEventChannel
}

struct HostConnection: Sendable, Equatable {
    let endpoint: URL
    let build: SupportedHostBuildCatalog.Build
    let compatibility: HostCompatibility
    let context: HostConnectionContext
    let startedAt: Date
    let diagnostics: HostDiagnosticRecorder

    var buildID: String { build.id }

    static func == (lhs: HostConnection, rhs: HostConnection) -> Bool {
        lhs.endpoint == rhs.endpoint && lhs.build == rhs.build && lhs.compatibility == rhs.compatibility && lhs.startedAt == rhs.startedAt
    }
}

struct HostUnverified: Equatable, Sendable {
    let reason: String
    let developerWriteOverrideEnabled: Bool
    let logPath: String
}

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
