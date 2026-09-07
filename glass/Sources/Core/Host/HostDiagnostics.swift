import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Copy-safe Host diagnostics. Endpoint data is reduced to a port and every
/// free-form error/compatibility reason is redacted before it enters storage.
struct HostDiagnosticSnapshot: Equatable, Sendable {
    let hostBuildID: String?
    let port: Int?
    let dshHome: String
    let ownedProcessID: Int32?
    let ownership: String
    let remoteGeneration: UInt64?
    let streamState: String
    let lastRPCError: String?
    let protocolFixtureRevision: String?
    let hostCompatibility: String
    let lifecycle: String

    func copyableText() -> String {
        [
            "hostBuild=\(hostBuildID ?? "unverified")",
            "port=\(port.map { String($0) } ?? "none")",
            "dshHome=\(dshHome)",
            "ownership=\(ownership)",
            "pid=\(ownedProcessID.map { String($0) } ?? "none")",
            "remoteGeneration=\(remoteGeneration.map(String.init) ?? "none")",
            "streamState=\(streamState)",
            "lastRPCError=\(lastRPCError ?? "none")",
            "protocolFixtureRevision=\(protocolFixtureRevision ?? "none")",
            "hostCompatibility=\(hostCompatibility)",
            "lifecycle=\(lifecycle)",
        ].joined(separator: "\n")
    }
}

/// Actor-isolated diagnostic facts shared by Host readiness and Remote calls.
/// Payload bodies, launch tokens, cookies and credential values never enter it.
actor HostDiagnosticRecorder {
    private let dshHome: String
    private var hostBuildID: String?
    private var port: Int?
    private var ownedProcessID: Int32?
    private var ownership = "none"
    private var remoteGeneration: UInt64?
    private var streamState = "disconnected"
    private var lastRPCError: String?
    private var protocolFixtureRevision: String?
    private var hostCompatibility = "unknown"
    private var lifecycle = "idle"

    init(dshHome: String) {
        self.dshHome = dshHome
    }

    func recordConnected(
        build: SupportedHostBuildCatalog.Build,
        compatibility: HostCompatibility,
        endpoint: URL,
        pid: Int32?,
        generation: RemoteConnectionGeneration? = nil
    ) {
        hostBuildID = build.id
        port = endpoint.port
        ownedProcessID = pid
        ownership = "owned"
        remoteGeneration = generation?.rawValue
        streamState = "ready"
        protocolFixtureRevision = build.protocolFixtureRevision
        switch compatibility {
        case .verified: hostCompatibility = "verified"
        case let .bestEffort(reason): hostCompatibility = "best-effort: \(HostLogRedactor.redact(reason))"
        }
        lifecycle = "ready"
    }

    func recordLifecycle(_ state: HostLifecycleState, ownedPID: Int32?) {
        lifecycle = stableStateName(state)
        ownedProcessID = ownedPID
        switch state {
        case .idle:
            ownership = "none"
            streamState = "disconnected"
            remoteGeneration = nil
        case .starting, .authenticating, .connecting, .classifying:
            streamState = "connecting"
        case .recovering:
            streamState = "recovering"
            remoteGeneration = nil
        case .ready:
            ownership = "owned"
        case .failed, .stopping:
            streamState = "disconnected"
            remoteGeneration = nil
        }
    }

    private func stableStateName(_ state: HostLifecycleState) -> String {
        switch state {
        case .idle: return "idle"
        case .starting: return "starting"
        case .authenticating: return "authenticating"
        case .connecting: return "connecting"
        case .classifying: return "classifying"
        case .recovering: return "recovering"
        case .ready: return "ready"
        case .failed: return "failed"
        case .stopping: return "stopping"
        }
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
            remoteGeneration: remoteGeneration,
            streamState: streamState,
            lastRPCError: lastRPCError,
            protocolFixtureRevision: protocolFixtureRevision,
            hostCompatibility: hostCompatibility,
            lifecycle: lifecycle
        )
    }
}

enum HostLogRedactor {
    private struct Rule {
        let expression: NSRegularExpression
        let replacementTemplate: String

        init(pattern: String, replacementTemplate: String) {
            self.expression = try! NSRegularExpression(pattern: pattern)
            self.replacementTemplate = replacementTemplate
        }
    }

    // Compile once at process initialization. Each rule owns its replacement
    // semantics so reordering or changing a pattern cannot silently select the
    // wrong template through pattern-string inspection.
    private static let rules: [Rule] = [
        .init(
            pattern: #"(?i)\bauthorization\s*:\s*bearer\s+[A-Za-z0-9._~+\-/=]+"#,
            replacementTemplate: "<redacted>"
        ),
        .init(
            pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+\-/=]+"#,
            replacementTemplate: "<redacted>"
        ),
        .init(
            pattern: #"(?i)\"(?:api[_-]?key|cookie|token|secret|password)\"\s*:\s*\"(?:\\.|[^\"])*\""#,
            replacementTemplate: "\"<redacted>\""
        ),
        .init(
            pattern: #"(?i)\b(api[_-]?key|cookie|token|secret|password)\s*[:=]\s*([^\s,;]+)"#,
            replacementTemplate: "<redacted>"
        ),
        .init(
            pattern: #"(?i)(https?://)[^\s/@:]+:[^\s/@]+@"#,
            replacementTemplate: "$1<redacted>@"
        ),
    ]

    static func redact(_ text: String) -> String {
        rules.reduce(text) { result, rule in
            let range = NSRange(result.startIndex..., in: result)
            return rule.expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacementTemplate
            )
        }
    }
}
