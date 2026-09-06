import Foundation

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
