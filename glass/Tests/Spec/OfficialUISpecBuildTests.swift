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
}
