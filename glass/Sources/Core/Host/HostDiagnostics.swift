import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// The copy-safe Host diagnostics payload. It deliberately records only an
/// endpoint port, never a full URL with possible query/user-info credentials.
struct HostDiagnosticSnapshot: Equatable, Sendable {
    let hostBuildID: String?
    let port: Int?
    let dshHome: String
    let ownedProcessID: Int32?
    let ownership: String
    let lastSSEAt: Date?
    let lastRPCError: String?
    let protocolFixtureRevision: String?
    let pluginCompatibility: String
    let lifecycle: String

    func copyableText() -> String {
        [
            "hostBuild=\(hostBuildID ?? "unverified")",
            "port=\(port.map { String($0) } ?? "none")",
            "dshHome=\(dshHome)",
            "ownership=\(ownership)",
            "pid=\(ownedProcessID.map { String($0) } ?? "none")",
            "lastSSEAt=\(lastSSEAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none")",
            "lastRPCError=\(lastRPCError ?? "none")",
            "protocolFixtureRevision=\(protocolFixtureRevision ?? "none")",
            "pluginCompatibility=\(pluginCompatibility)",
            "lifecycle=\(lifecycle)",
        ].joined(separator: "\n")
    }
}

/// Actor-isolated diagnostic facts shared by Host readiness, RPC facade and SSE
/// observation. It stores redacted summaries only and never payload bodies.
actor HostDiagnosticRecorder {
    private let dshHome: String
    private var hostBuildID: String?
    private var port: Int?
    private var ownedProcessID: Int32?
    private var ownership = "none"
    private var lastSSEAt: Date?
    private var lastRPCError: String?
    private var protocolFixtureRevision: String?
    private var pluginCompatibility = "unknown"
    private var lifecycle = "idle"

    init(dshHome: String) {
        self.dshHome = dshHome
    }

    func recordVerified(build: SupportedHostBuildCatalog.Build, endpoint: URL, pid: Int32?) {
        hostBuildID = build.id
        port = endpoint.port
        ownedProcessID = pid
        ownership = "owned"
        protocolFixtureRevision = build.protocolFixtureRevision
        pluginCompatibility = "pinned-compatible"
        lifecycle = "ready"
    }

    func recordUnverified(reason: String) {
        hostBuildID = nil
        pluginCompatibility = "unverified: \(HostLogRedactor.redact(reason))"
        lifecycle = "unverified"
    }

    func recordLifecycle(_ state: HostLifecycleState, ownedPID: Int32?) {
        lifecycle = HostLifecycleTransition(from: state, to: state, at: Date()).summary.components(separatedBy: " -> ").last ?? "unknown"
        ownedProcessID = ownedPID
        if case .ready = state { ownership = "owned" }
        if case .idle = state { ownership = "none" }
    }

    func recordSSEActivity(at date: Date = Date()) {
        lastSSEAt = date
    }

    func recordRPCError(_ error: Error) {
        lastRPCError = HostLogRedactor.redact(error.localizedDescription)
    }

    func snapshot() -> HostDiagnosticSnapshot {
        HostDiagnosticSnapshot(
            hostBuildID: hostBuildID,
            port: port,
            dshHome: dshHome,
            ownedProcessID: ownedProcessID,
            ownership: ownership,
            lastSSEAt: lastSSEAt,
            lastRPCError: lastRPCError,
            protocolFixtureRevision: protocolFixtureRevision,
            pluginCompatibility: pluginCompatibility,
            lifecycle: lifecycle
        )
    }
}

enum HostLogRedactor {
    /// Compiled once per process. `NSRegularExpression` is documented
    /// thread-safe, and `redact` is called from an actor-isolated recorder.
    private static let patterns: [NSRegularExpression] = [
        #"(?i)\bauthorization\s*:\s*bearer\s+[A-Za-z0-9._~+\-/=]+"#,
        #"(?i)\bbearer\s+[A-Za-z0-9._~+\-/=]+"#,
        #"(?i)\b(api[_-]?key|cookie|token|secret|password)\s*[:=]\s*([^\s,;]+)"#,
        #"(?i)(https?://)[^\s/@:]+:[^\s/@]+@"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func redact(_ text: String) -> String {
        var result = text
        for expression in patterns {
            let range = NSRange(result.startIndex..., in: result)
            let template: String
            if expression.pattern.hasPrefix("(?i)(https") {
                template = "$1<redacted>@"
            } else {
                template = "<redacted>"
            }
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}
