import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativePluginCardDraftTests: XCTestCase {
    private let timeout = NativePluginCardField("timeoutMs", kind: .number)
    private let outputCap = NativePluginCardField("maxOutputBytes", kind: .number)
    private let secret = NativePluginCardField("apiKey", kind: .text)

    func testStagesMultipleTypedFieldsWithoutWritingAuthority() {
        var draft = NativePluginCardDraft(
            namespace: shellNamespace(user: [:]),
            fields: [timeout, outputCap]
        )

        draft.stage("9000", for: timeout)
        draft.stage("1024", for: outputCap)

        XCTAssertTrue(draft.isDirty)
        XCTAssertFalse(draft.hasInvalidDraft)
        XCTAssertEqual(
            draft.mutationPlan,
            [
                .set(path: ["maxOutputBytes"], value: .number(1024)),
                .set(path: ["timeoutMs"], value: .number(9000)),
            ]
        )
        XCTAssertEqual(draft.namespace.value, .object(["timeoutMs": .number(60000), "maxOutputBytes": .number(64000)]))
    }

    func testResetAndBlankDraftClearOnlyUserOverrides() {
        var reset = NativePluginCardDraft(
            namespace: shellNamespace(user: ["timeoutMs": .number(9000)]),
            fields: [timeout]
        )
        reset.reset(timeout)

        XCTAssertEqual(reset.state(for: timeout), .init(text: "120000", overridden: false, invalid: false))
        XCTAssertEqual(reset.mutationPlan, [.unset(path: ["timeoutMs"])])

        var blank = NativePluginCardDraft(
            namespace: shellNamespace(user: ["timeoutMs": .number(9000)]),
            fields: [timeout]
        )
        blank.stage("  ", for: timeout)
        XCTAssertFalse(blank.hasInvalidDraft)
        XCTAssertEqual(blank.mutationPlan, [.unset(path: ["timeoutMs"])])
    }

    func testInvalidNumberBlocksSaveUntilDiscarded() {
        var draft = NativePluginCardDraft(namespace: shellNamespace(user: [:]), fields: [timeout])
        draft.stage("soon", for: timeout)

        XCTAssertTrue(draft.isDirty)
        XCTAssertTrue(draft.hasInvalidDraft)
        XCTAssertNil(draft.mutationPlan)
        XCTAssertEqual(draft.state(for: timeout), .init(text: "soon", overridden: false, invalid: true))

        draft.discard()
        XCTAssertFalse(draft.isDirty)
        XCTAssertFalse(draft.hasInvalidDraft)
        XCTAssertEqual(draft.mutationPlan, [])
    }

    func testSecretRoleIsExcludedFromSettingsDraftAndCannotEnterMutationPlan() {
        var draft = NativePluginCardDraft(
            namespace: SettingsNamespaceDTO(
                ns: "web-search-deepseek",
                schema: .object([:]),
                value: .object(["baseURL": .string("https://search.test")]),
                base: nil,
                user: nil,
                applies: "live",
                secrets: [.init(path: ["apiKey"], set: true)],
                revision: 2
            ),
            fields: [secret, .init("baseURL", kind: .text)]
        )

        draft.stage("must-not-retain", for: secret)
        XCTAssertFalse(draft.isDirty)
        XCTAssertNil(draft.state(for: secret))
        XCTAssertEqual(draft.mutationPlan, [])
    }

    private func shellNamespace(user: [String: JSONValue]) -> SettingsNamespaceDTO {
        .init(
            ns: "shell",
            schema: .object([:]),
            value: .object(["timeoutMs": .number(60000), "maxOutputBytes": .number(64000)]),
            base: .object(["timeoutMs": .number(120000), "maxOutputBytes": .number(64000)]),
            user: .object(user),
            applies: "live",
            secrets: [],
            revision: 4
        )
    }
}
