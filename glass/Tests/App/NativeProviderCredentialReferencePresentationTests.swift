import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeProviderCredentialReferencePresentationTests: XCTestCase {
    func testReferencesComeOnlyFromHostResolvedProviderProfilesInDirectoryOrder() {
        let providers = [
            provider(id: "first", namespace: "llm", path: ["providers", "first"]),
            provider(id: "second", namespace: "llm", path: ["providers", "second"]),
            provider(id: "missing", namespace: "llm", path: ["providers", "missing"]),
        ]
        let namespace = settingsNamespace(value: .object([
            "providers": .object([
                "first": .object(["apiKeyEnv": .string("FIRST_KEY")]),
                "second": .object(["apiKeyEnv": .string("FIRST_KEY")]),
            ]),
        ]))

        XCTAssertEqual(
            NativeProviderCredentialReferencePresentation.references(for: providers, namespaces: [namespace]),
            ["FIRST_KEY"]
        )
        XCTAssertEqual(
            NativeProviderCredentialReferencePresentation.reference(for: providers[0], namespaces: [namespace]),
            "FIRST_KEY"
        )
        XCTAssertNil(NativeProviderCredentialReferencePresentation.reference(for: providers[2], namespaces: [namespace]))
    }

    func testMalformedOrEmptyProfileReferenceDoesNotInventProviderFallback() {
        let provider = provider(id: "route-id", namespace: "llm", path: ["providers", "route-id"])
        let blank = settingsNamespace(value: .object([
            "providers": .object(["route-id": .object(["apiKeyEnv": .string("   ")])]),
        ]))
        let malformed = settingsNamespace(value: .object([
            "providers": .object(["route-id": .object(["apiKeyEnv": .number(1)])]),
        ]))

        XCTAssertNil(NativeProviderCredentialReferencePresentation.reference(for: provider, namespaces: [blank]))
        XCTAssertNil(NativeProviderCredentialReferencePresentation.reference(for: provider, namespaces: [malformed]))
    }

    private func provider(id: String, namespace: String, path: [String]) -> LLMProviderDTO {
        .init(provider: id, displayName: id, settingsNs: namespace, settingsPath: path, active: true, declared: false)
    }

    private func settingsNamespace(value: JSONValue) -> SettingsNamespaceDTO {
        .init(
            ns: "llm",
            schema: .object([:]),
            value: value,
            base: nil,
            user: nil,
            applies: "user",
            secrets: [],
            revision: 1
        )
    }
}
