import Foundation

/// One authenticated Host generation published to the business composition
/// root. Authentication, Host facts, compatibility and diagnostics travel
/// together so a ready connection cannot mix facts from different generations.
struct HostConnectionContext: Sendable {
    let authenticatedHost: AuthenticatedHostSession
    let remote: RemoteConnection
    let events: RemoteEventChannel
    let compatibility: HostCompatibility
    let diagnostics: HostDiagnosticRecorder

    var baseURL: URL { authenticatedHost.baseURL }
    var hostFacts: RemoteHostFacts { events.ready.host }
    var generation: RemoteConnectionGeneration { events.generation }
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
