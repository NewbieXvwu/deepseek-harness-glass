import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeCredentialStatusPresentationTests: XCTestCase {
    func testConfiguredWritableCredentialUsesOfficialReplacementHint() {
        let credential = CredentialViewDTO(configured: true, source: "keychain", writable: true)

        XCTAssertTrue(NativeCredentialStatusPresentation.isEditable(credential))
        XCTAssertEqual(
            NativeCredentialStatusPresentation.statusText(credential),
            OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: "keyStored", language: "en")
        )
    }

    func testEnvironmentCredentialIsReadOnlyAndDoesNotExposeSourceAsValue() {
        let credential = CredentialViewDTO(configured: true, source: "environment", writable: false)

        XCTAssertFalse(NativeCredentialStatusPresentation.isEditable(credential))
        XCTAssertEqual(
            NativeCredentialStatusPresentation.statusText(credential),
            OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: "keyEnvLocked", language: "en")
        )
        XCTAssertFalse(NativeCredentialStatusPresentation.statusText(credential).contains("environment"))
    }

    func testUnconfiguredWritableCredentialUsesOfficialWriteOnlyPlaceholder() {
        let credential = CredentialViewDTO(configured: false, source: nil, writable: true)

        XCTAssertTrue(NativeCredentialStatusPresentation.isEditable(credential))
        XCTAssertEqual(
            NativeCredentialStatusPresentation.statusText(credential),
            OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: "keyPlaceholderNative", language: "en")
        )
    }
}
