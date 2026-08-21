import XCTest

@testable import GlassUI

@MainActor
final class NativeJobsHeaderActionTests: XCTestCase {
    func testSnapshotLanguageOverridePinsOfficialEnglishCapture() {
        XCTAssertEqual(
            NativeJobsHeaderAction.resolvedLanguageCode(override: "en", current: "zh"),
            "en"
        )
    }

    func testProductionLanguageFallsBackToCurrentOfficialCatalogLanguage() {
        XCTAssertEqual(
            NativeJobsHeaderAction.resolvedLanguageCode(override: nil, current: "zh"),
            "zh"
        )
        XCTAssertEqual(
            NativeJobsHeaderAction.resolvedLanguageCode(override: nil, current: "en"),
            "en"
        )
    }

    func testUnsupportedCaptureOverrideFallsBackToCurrentOfficialLanguage() {
        XCTAssertEqual(
            NativeJobsHeaderAction.resolvedLanguageCode(override: "unsupported", current: "zh"),
            "zh"
        )
    }

    func testPopoverListAccessibilityLabelUsesLockedJobsCatalog() {
        XCTAssertEqual(
            NativeJobsHeaderAction.localizedValue(key: "list.aria", language: "en"),
            "Background jobs"
        )
        XCTAssertEqual(
            NativeJobsHeaderAction.localizedValue(key: "list.aria", language: "zh"),
            "后台任务"
        )
    }
}
