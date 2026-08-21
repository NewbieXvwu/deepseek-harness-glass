import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeWebSearchCredentialPresentationTests: XCTestCase {
    func testProjectionUsesServedReferenceAndNeverReadsCredentialValue() {
        let presentation = NativeWebSearchCredentialPresentation.project(
            namespace: webSearchNamespace(apiKeyEnv: "SEARCH_KEY"),
            credential: .init(configured: true, source: "keychain", writable: true)
        )

        XCTAssertEqual(presentation?.reference, "SEARCH_KEY")
        XCTAssertTrue(presentation?.configured == true)
        XCTAssertTrue(presentation?.writable == true)
    }

    func testBlankReferenceUsesOfficialProviderDefaultAndUnknownStatusRemainsWritable() {
        let presentation = NativeWebSearchCredentialPresentation.project(
            namespace: webSearchNamespace(apiKeyEnv: " "),
            credential: nil
        )

        XCTAssertEqual(presentation?.reference, "DEEPSEEK_API_KEY")
        XCTAssertFalse(presentation?.configured == true)
        XCTAssertTrue(presentation?.writable == true)
    }

    func testEnvironmentCredentialIsReadOnlyAndOtherNamespacesCannotProject() {
        let locked = NativeWebSearchCredentialPresentation.project(
            namespace: webSearchNamespace(apiKeyEnv: "DEEPSEEK_API_KEY"),
            credential: .init(configured: true, source: "environment", writable: false)
        )
        let unrelated = NativeWebSearchCredentialPresentation.project(
            namespace: SettingsNamespaceDTO(
                ns: "shell", schema: .object([:]), value: .object([:]), base: nil, user: nil,
                applies: "live", secrets: [], revision: 1
            ),
            credential: nil
        )

        XCTAssertTrue(locked?.configured == true)
        XCTAssertFalse(locked?.writable == true)
        XCTAssertNil(unrelated)
    }

    private func webSearchNamespace(apiKeyEnv: String) -> SettingsNamespaceDTO {
        .init(
            ns: "web-search-deepseek",
            schema: .object([:]),
            value: .object(["apiKeyEnv": .string(apiKeyEnv)]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [.init(path: ["apiKey"], set: true)],
            revision: 1
        )
    }
}
