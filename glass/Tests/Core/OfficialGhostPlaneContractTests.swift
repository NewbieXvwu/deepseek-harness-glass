import Foundation
import XCTest
@testable import GlassCore
@testable import GlassSpec

final class OfficialGhostPlaneContractTests: XCTestCase {
    func testGeneratedContractMatchesLockedBuildAndSkeletonSelectorInventory() throws {
        let fixture = try OfficialGhostPlaneContract.load()
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
