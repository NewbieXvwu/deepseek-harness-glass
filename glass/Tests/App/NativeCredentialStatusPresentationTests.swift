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
            // The official env-locked copy itself names the environment source,
            // so presence of the word is expected; the source is only ever shown
            // through that locked locale text, never as a free-form value.
            OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: "keyEnvLocked", language: "en")
        )
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
