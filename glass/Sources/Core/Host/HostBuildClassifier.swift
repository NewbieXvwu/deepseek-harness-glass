import Foundation

/// Pure rc.1 support classification. Filesystem discovery stays in
/// `HostBuildVerifier`; Attach/Adopt/Install can reuse this classifier once they
/// have discovered package versions from another installation source.
struct HostBuildClassifier: Sendable {
    private static let lockedOfficialSourceCommit = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"

    /// Structural catalog validation is safe before a Host exists. Package-version
    /// compatibility is intentionally excluded so it can be classified only after
    /// authenticated rc.1 Remote readiness has been established.
    func catalogValidationError(for build: SupportedHostBuildCatalog.Build) -> String? {
        guard build.officialSourceCommit == Self.lockedOfficialSourceCommit else {
            return "Bundled Host catalog does not match the locked official source commit."
        }
        guard !build.dshPackageVersion.isEmpty,
              !build.webFrontendPackageVersion.isEmpty,
              !build.nodeRuntimeVersion.isEmpty,
              !build.protocolFixtureRevision.isEmpty,
              !build.uiSpecRevision.isEmpty,
              !build.minimumAppVersion.isEmpty else {
            return "Bundled Host catalog is missing fixed payload support metadata."
        }
        return nil
    }

    func classify(
        build: SupportedHostBuildCatalog.Build,
        dshVersion: String?,
        webFrontendVersion: String?
    ) -> HostBuildVerification {
        if let reason = catalogValidationError(for: build) {
            return .unsupported(reason: reason)
        }
        guard let dshVersion, let webFrontendVersion else {
            return .bestEffort(
                build,
                reason: "Host package metadata is unavailable; attempting the rc.1 Remote contract best-effort."
            )
        }
        guard dshVersion == build.dshPackageVersion,
              webFrontendVersion == build.webFrontendPackageVersion else {
            return .bestEffort(
                build,
                reason: "Host package facts differ from the verified rc.1 catalog; attempting the rc.1 Remote contract best-effort."
            )
        }
        if build.verificationState == "verified" { return .verified(build) }
        return .bestEffort(build, reason: "Bundled rc.1 payload matches the supported build but macOS verification is still pending.")
    }
}
