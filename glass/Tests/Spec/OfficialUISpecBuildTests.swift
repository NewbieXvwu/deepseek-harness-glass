import XCTest
@testable import GlassSpec

final class OfficialUISpecBuildTests: XCTestCase {
    func testGeneratedBuildIdentityIsCompleteAndSelfCompatible() {
        XCTAssertEqual(OfficialUISpec.deepSeekHarnessCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(OfficialUISpec.hostBuildID, OfficialUISpec.Build.id)
        XCTAssertTrue(OfficialUISpec.Build.isCompatible(with: OfficialUISpec.hostBuildID))
        XCTAssertFalse(OfficialUISpec.Build.isCompatible(with: "unknown-host-build"))
        XCTAssertTrue(OfficialUISpec.Build.localeRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.tokenRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.layoutRevision.hasPrefix("sha256:"))
        XCTAssertTrue(OfficialUISpec.Build.fixtureRevision.hasPrefix("sha256:"))
        XCTAssertEqual(OfficialUISpec.Build.sourceCommit.count, 40)
        XCTAssertFalse(OfficialUISpec.Build.uiSpecRevision.isEmpty)
    }

    func testGeneratedBilingualLocaleCatalogIsQueryableAndMatchesBuildRevision() {
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.sourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.revision, OfficialUISpec.Build.localeRevision)
        XCTAssertTrue(OfficialUISpec.LocaleCatalog.contains(namespace: "ui-sidebar", key: "session.new", language: "en"))
        XCTAssertTrue(OfficialUISpec.LocaleCatalog.contains(namespace: "ui-sidebar", key: "session.new", language: "zh"))
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "session.new", language: "en"), "New Session")
        XCTAssertEqual(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "session.new", language: "zh"), "新会话")
        XCTAssertNil(OfficialUISpec.LocaleCatalog.value(namespace: "ui-sidebar", key: "not.registered", language: "en"))
    }
}
