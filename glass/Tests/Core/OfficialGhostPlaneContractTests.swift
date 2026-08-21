import Foundation
import XCTest
@testable import GlassCore
@testable import GlassSpec

final class OfficialGhostPlaneContractTests: XCTestCase {
    func testGeneratedContractMatchesLockedBuildAndSkeletonSelectorInventory() throws {
        let fixture = try OfficialGhostPlaneContract.load()

        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.sourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertGreaterThanOrEqual(fixture.sources.count, 6)
        XCTAssertEqual(fixture.moduleLoader.bootGlobal, "__DSH_BOOT__")
        XCTAssertEqual(fixture.moduleLoader.registrationGlobal, "__ModuleLoader__")
        XCTAssertEqual(fixture.moduleLoader.registrationMethod, "load")
        XCTAssertEqual(fixture.moduleLoader.bundlePathTemplate, "/plugins/<id>/client.js?rev=<rev>")
        XCTAssertTrue(fixture.moduleLoader.factoryRegistration)
        XCTAssertNoThrow(try OfficialGhostPlaneContract.validateSkeletonSelectors(GhostPlaneSkeleton.requiredSelectors, against: fixture))
    }

    func testSelectorDriftReportsMissingAndUnexpectedValues() throws {
        let fixture = try OfficialGhostPlaneContract.load()
        let actual = GhostPlaneSkeleton.requiredSelectors.filter { $0 != "[data-streaming]" } + ["[data-unreviewed]"]

        XCTAssertThrowsError(try OfficialGhostPlaneContract.validateSkeletonSelectors(actual, against: fixture)) { error in
            XCTAssertEqual(
                error as? OfficialGhostPlaneContract.ValidationError,
                .skeletonSelectorDrift(missing: ["[data-streaming]"], unexpected: ["[data-unreviewed]"])
            )
        }
    }
}
