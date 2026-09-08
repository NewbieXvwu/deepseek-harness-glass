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
            streamState = "ready"
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

/// Masks credential-shaped substrings before host diagnostics reach the log.
/// Host stderr can echo the bootstrap URL and request headers, so a single
/// linear scan masks the value that follows a small set of literal markers.
/// Keys the loopback host never emits (URL userinfo, exotic auth schemes) are
/// deliberately not modeled.
enum HostLogRedactor {
    private static let markers = [
        "\"api_key\"", "\"apikey\"", "api_key=", "apikey=",
        "\"token\"", "token=", "bearer ",
        "\"cookie\"", "cookie=",
        "\"secret\"", "secret=",
        "\"password\"", "password=",
    ]

    static func redact(_ text: String) -> String {
        var output = ""
        var rest = Substring(text)
        while let marker = firstMarker(in: rest) {
            var valueStart = marker.upperBound
            var quoted = false
            while valueStart < rest.endIndex, isSeparator(rest[valueStart]) {
                if rest[valueStart] == "\"" { quoted = true }
                valueStart = rest.index(after: valueStart)
            }
            guard valueStart < rest.endIndex else {
                return output + rest
            }
            output += rest[rest.startIndex..<valueStart]
            output += "<redacted>"
            var valueEnd = valueStart
            if quoted {
                while valueEnd < rest.endIndex {
                    let character = rest[valueEnd]
                    if character == "\\" {
                        valueEnd = rest.index(after: valueEnd)
                        if valueEnd < rest.endIndex { valueEnd = rest.index(after: valueEnd) }
                    } else if character == "\"" {
                        break
                    } else {
                        valueEnd = rest.index(after: valueEnd)
                    }
                }
            } else {
                while valueEnd < rest.endIndex, !isDelimiter(rest[valueEnd]) {
                    valueEnd = rest.index(after: valueEnd)
                }
            }
            rest = rest[valueEnd...]
        }
        return output + rest
    }

    private static func firstMarker(in text: Substring) -> Range<String.Index>? {
        var earliest: Range<String.Index>?
        for marker in markers {
            guard let range = text.range(of: marker, options: .caseInsensitive) else { continue }
            if earliest.map({ range.lowerBound < $0.lowerBound }) ?? true {
                earliest = range
            }
        }
        return earliest
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == ":" || character == "=" || character == " " || character == "\"" || character == "'"
    }

    private static func isDelimiter(_ character: Character) -> Bool {
        character == "&" || character == "," || character == ";" || character == "\"" || character.isWhitespace
    }
}
