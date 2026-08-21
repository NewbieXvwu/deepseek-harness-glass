import Foundation

/// Pure planning layer for the Attach → Adopt → Install runtime ladder. It has
/// no process, network or filesystem side effects; `HarnessHostController` is
/// the sole lifecycle owner that may execute the chosen plan.
struct HostRuntimeLadder: Sendable {
    struct Candidate: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case attach(endpoint: URL), adopt(executable: URL), install }
        let kind: Kind
        /// Only an exact locked build is permitted to receive verified writes.
        /// Attach candidates may leave this nil until their diagnostic probe.
        let buildID: String?
        init(kind: Kind, buildID: String? = nil) {
            self.kind = kind
            self.buildID = buildID
        }
    }

    enum Access: Equatable, Sendable { case verified, readOnly(reason: String) }
    enum Plan: Equatable, Sendable {
        case attach(endpoint: URL, access: Access)
        case adopt(executable: URL, access: Access)
        case install(access: Access)
    }

    let lockedBuildID: String

    func select(attach: Candidate?, adopt: Candidate?, install: Candidate?) -> Plan? {
        if let attach, case let .attach(endpoint) = attach.kind {
            return .attach(endpoint: endpoint, access: access(for: attach, mode: "Attached"))
        }
        if let adopt, case let .adopt(executable) = adopt.kind {
            return .adopt(executable: executable, access: access(for: adopt, mode: "Adopted"))
        }
        if let install, case .install = install.kind {
            return .install(access: access(for: install, mode: "Installed"))
        }
        return nil
    }

    private func access(for candidate: Candidate, mode: String) -> Access {
        guard candidate.buildID == lockedBuildID else {
            let actual = candidate.buildID ?? "unknown"
            return .readOnly(reason: "\(mode) Host build \(actual) is not locked build \(lockedBuildID).")
        }
        return .verified
    }
}
