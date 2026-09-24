import Foundation

/// One authenticated Host generation published to the business composition
/// root. Authentication, Remote readiness and diagnostics travel together so a
/// ready connection cannot mix facts from different generations.
struct HostConnectionContext: Sendable {
    let authenticatedHost: AuthenticatedHostSession
    let remote: RemoteConnection
    let events: RemoteEventChannel
    let diagnostics: HostDiagnosticRecorder

    var baseURL: URL { authenticatedHost.baseURL }
    var hostFacts: RemoteHostFacts { events.ready.host }
    var generation: RemoteConnectionGeneration { events.generation }
}

struct HostConnection: Sendable, Equatable {
    let endpoint: URL
    let context: HostConnectionContext
    let startedAt: Date
    let diagnostics: HostDiagnosticRecorder

    static func == (lhs: HostConnection, rhs: HostConnection) -> Bool {
        lhs.endpoint == rhs.endpoint && lhs.startedAt == rhs.startedAt
    }
}
