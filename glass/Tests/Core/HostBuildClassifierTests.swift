import XCTest
@testable import GlassCore

final class HostBuildClassifierTests: XCTestCase {
    func testVerifiedRc1BuildIsAccepted() {
        XCTAssertEqual(
            HostBuildClassifier().classify(
                build: Self.build(verificationState: "verified"),
                dshVersion: "0.1.2-rc.1",
                webFrontendVersion: "0.1.2-rc.1"
            ),
            .verified(Self.build(verificationState: "verified"))
        )
    }

    func testPlannedRc1BuildIsBestEffort() {
        let build = Self.build(verificationState: "planned")
        guard case let .bestEffort(classified, reason) = HostBuildClassifier().classify(
            build: build,
            dshVersion: "0.1.2-rc.1",
            webFrontendVersion: "0.1.2-rc.1"
        ) else { return XCTFail("a planned rc.1 build must remain best-effort") }
        XCTAssertEqual(classified, build)
        XCTAssertFalse(reason.isEmpty)
    }

    func testRejectsWrongSourceCommitAndPackageVersions() {
        var build = Self.build(verificationState: "verified", officialSourceCommit: "wrong")
        guard case let .unsupported(reason) = HostBuildClassifier().classify(
            build: build,
            dshVersion: "0.1.2-rc.1",
            webFrontendVersion: "0.1.2-rc.1"
        ) else { return XCTFail("wrong source commit must be unsupported") }
        XCTAssertTrue(reason.contains("commit"))

        build = Self.build(verificationState: "verified")
        guard case let .bestEffort(mismatched, _) = HostBuildClassifier().classify(
            build: build,
            dshVersion: "0.1.2-incompatible",
            webFrontendVersion: "0.1.2-rc.1"
        ) else { return XCTFail("mismatched package facts must be best-effort") }
        XCTAssertEqual(mismatched, build)

        guard case let .bestEffort(unavailable, _) = HostBuildClassifier().classify(
            build: build,
            dshVersion: nil,
            webFrontendVersion: nil
        ) else { return XCTFail("missing package metadata must be best-effort") }
        XCTAssertEqual(unavailable, build)
    }

    private static func build(
        verificationState: String,
        officialSourceCommit: String = "a66e4702047846cdaa10c66c9d3df3951f5ea70d"
    ) -> SupportedHostBuildCatalog.Build {
        .init(
            id: "dsh-0.1.2-rc.1-official-a66e470",
            officialSourceCommit: officialSourceCommit,
            dshPackageVersion: "0.1.2-rc.1",
            webFrontendPackageVersion: "0.1.2-rc.1",
            nodeRuntimeVersion: "24.19.0",
            minimumAppVersion: "0.4.0",
            minimumMacOS: "26.0",
            ciRunner: "macos-26",
            minimumXcodeMajor: 26,
            protocolFixtureRevision: "official-a66e470-remote-r1",
            uiSpecRevision: "official-a66e470-ui-spec-r1",
            supportedArchitectures: ["arm64"],
            verifiedAt: verificationState == "verified" ? "2026-08-18" : nil,
            verificationState: verificationState
        )
    }
}
