import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeModelDirectoryFailurePresentationTests: XCTestCase {
    func testEmptyHostFailureListDoesNotManufactureSettingsError() {
        XCTAssertTrue(NativeModelDirectoryFailurePresentation.project([]).isEmpty)
    }
}
