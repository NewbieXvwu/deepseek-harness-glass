import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Authority assigned to a Host payload after local manifest and package metadata
/// validation. Unverified payloads are deliberately diagnostic-only by default.
enum HostBuildTrust: Equatable, Sendable {
    case verified(SupportedHostBuildCatalog.Build)
    case unverified(reason: String, developerWriteOverride: Bool)

    var buildID: String? {
        if case let .verified(build) = self { return build.id }
        return nil
    }

    var permitsWrites: Bool {
        switch self {
        case .verified: return true
        case let .unverified(_, developerWriteOverride): return developerWriteOverride
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .verified(build): return "verified \(build.id)"
        case let .unverified(reason, developerWriteOverride):
            return developerWriteOverride ? "unverified override enabled: \(reason)" : "unverified write-protected: \(reason)"
        }
    }
}

/// Transport-level enforcement for the build support boundary. This policy is
/// injected explicitly into every native transport instance, so unknown Hosts
/// cannot accidentally receive a write RPC through a URL-only client.
struct HostRPCAccessPolicy: Equatable, Sendable {
    let trust: HostBuildTrust

    static let diagnosticsOnly = HostRPCAccessPolicy(
        trust: .unverified(reason: "No Host build verification has completed.", developerWriteOverride: false)
    )

    func permits(method: String) -> Bool {
        if trust.permitsWrites { return true }
        // `host.describe` is the sole pre-trust request: it is needed to expose
        // diagnosis but has no mutation semantics.
        return method == "host.describe"
    }
}
