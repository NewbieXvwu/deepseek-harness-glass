import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeModelDirectoryFailurePresentationTests: XCTestCase {
    func testModelDirectoryFailureUsesLockedTitleAndHostSafeFailureOnly() {
        let failures = [
            LLMModelFailureDTO(id: "deepseek", name: "DeepSeek", message: "Host refused discovery"),
        ]

        let presentation = NativeModelDirectoryFailurePresentation.project(failures)

        XCTAssertEqual(
            NativeModelDirectoryFailurePresentation.title,
            OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: "loadFailed", language: "en")
        )
        XCTAssertEqual(presentation, [.init(id: "deepseek", name: "DeepSeek", message: "Host refused discovery")])
    }

    func testEmptyHostFailureListDoesNotManufactureSettingsError() {
        XCTAssertTrue(NativeModelDirectoryFailurePresentation.project([]).isEmpty)
    }
}
