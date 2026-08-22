import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeBuiltinPluginCardCatalogTests: XCTestCase {
    func testOnlyServedOfficialBuiltinNamespacesDispatchInOfficialRegistrationOrder() {
        let cards = NativeBuiltinPluginCard.dispatched(from: [
            namespace("web-search-deepseek"),
            namespace("unclaimed-plugin"),
            namespace("shell"),
            namespace("agent-loop"),
        ])

        XCTAssertEqual(cards, [.bash, .agentLoop, .webSearch])
        XCTAssertEqual(cards.map(\.namespace), ["shell", "agent-loop", "web-search-deepseek"])
    }

    func testNoServedBuiltinNamespaceProducesNoPlaceholderCard() {
        XCTAssertTrue(NativeBuiltinPluginCard.dispatched(from: [namespace("unclaimed-plugin")]).isEmpty)
    }

    func testBuiltinCardsDeclareOnlyTheirReviewedSettingsFields() {
        XCTAssertEqual(
            NativeBuiltinPluginCard.bash.fields.map(\.path),
            [["timeoutMs"], ["maxOutputBytes"]]
        )
        XCTAssertEqual(
            NativeBuiltinPluginCard.agentLoop.fields.map(\.path),
            [["maxParallelToolCalls"]]
        )
        XCTAssertEqual(
            NativeBuiltinPluginCard.webSearch.fields.map(\.path),
            [["baseURL"], ["maxUses"]]
        )
        XCTAssertFalse(NativeBuiltinPluginCard.webSearch.fields.map(\.path).contains(["apiKey"]))
    }

    private func namespace(_ name: String) -> SettingsNamespaceDTO {
        .init(
            ns: name,
            schema: .object([:]),
            value: .object([:]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [],
            revision: 1
        )
    }
}
