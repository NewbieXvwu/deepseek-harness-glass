import Foundation

/// Pure rc.1 support classification. Filesystem discovery stays in
/// `HostBuildVerifier`; Attach/Adopt/Install can reuse this classifier once they
/// have discovered package versions from another installation source.
struct HostBuildClassifier: Sendable {
    private static let lockedOfficialSourceCommit = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"

    func classify(
        build: SupportedHostBuildCatalog.Build,
        dshVersion: String,
        webFrontendVersion: String
    ) -> HostBuildVerification {
        guard build.officialSourceCommit == Self.lockedOfficialSourceCommit else {
            return .unsupported(reason: "Bundled Host catalog does not match the locked official source commit.")
        }
        guard !build.dshPackageVersion.isEmpty,
              !build.webFrontendPackageVersion.isEmpty,
              !build.nodeRuntimeVersion.isEmpty,
              !build.protocolFixtureRevision.isEmpty,
              !build.uiSpecRevision.isEmpty,
              !build.minimumAppVersion.isEmpty else {
            return .unsupported(reason: "Bundled Host catalog is missing fixed payload support metadata.")
        }
        guard dshVersion == build.dshPackageVersion else {
            return .unsupported(reason: "Bundled dsh package version does not match the supported Host catalog.")
        }
        guard webFrontendVersion == build.webFrontendPackageVersion else {
            return .unsupported(reason: "Bundled dsh web frontend version does not match the supported Host catalog.")
        }
        if build.verificationState == "verified" { return .verified(build) }
        return .bestEffort(build, reason: "Bundled rc.1 payload matches the supported build but macOS verification is still pending.")
    }
}
