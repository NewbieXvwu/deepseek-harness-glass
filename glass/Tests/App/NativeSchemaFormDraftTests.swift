@testable import GlassCore
import XCTest

@testable import GlassUI

final class NativeSchemaFormDraftTests: XCTestCase {
    func testDraftBuildsManifestOrderedTypedPlanAndLeavesUnchangedResetOut() {
        let manifest = fixtureManifest()
        let namespace = fixtureNamespace()
        let fields = Dictionary(uniqueKeysWithValues: manifest.fields.map { ($0.id, $0) })
        var draft = NativeSchemaFormDraft(namespace: namespace, manifest: manifest)

        draft.stageBoolean(true, for: fields["enabled"]!)
        draft.stageText("25", for: fields["timeout"]!)
        draft.stageText("safe", for: fields["mode"]!)
        draft.reset(fields["path"]!)

        XCTAssertEqual(draft.mutationPlan, [
            .set(path: ["enabled"], value: .bool(true)),
            .set(path: ["timeoutMs"], value: .number(25)),
            .set(path: ["mode"], value: .string("safe")),
        ])
    }

    func testInvalidSelectAndNumberBlockSaveWithoutDiscardingDraft() {
        let manifest = fixtureManifest()
        let fields = Dictionary(uniqueKeysWithValues: manifest.fields.map { ($0.id, $0) })
        var draft = NativeSchemaFormDraft(namespace: fixtureNamespace(), manifest: manifest)

        draft.stageText("unsafe", for: fields["mode"]!)
        XCTAssertTrue(draft.hasInvalidDraft)
        XCTAssertNil(draft.mutationPlan)
        XCTAssertTrue(draft.isDirty)

        draft.stageText("not-a-number", for: fields["timeout"]!)
        XCTAssertTrue(draft.state(for: fields["timeout"]!, writable: true)?.invalid == true)
        XCTAssertNil(draft.mutationPlan)
    }

    func testReadOnlyAndSecretManifestFieldsCannotEnterSettingsMutationPlan() {
        let manifest = fixtureManifest()
        let fields = Dictionary(uniqueKeysWithValues: manifest.fields.map { ($0.id, $0) })
        var draft = NativeSchemaFormDraft(namespace: fixtureNamespace(), manifest: manifest)

        draft.stageText("attempt", for: fields["readOnly"]!)
        draft.stageText("attempt", for: fields["secret"]!)

        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.state(for: fields["readOnly"]!, writable: true)?.writable, false)
        XCTAssertEqual(draft.state(for: fields["secret"]!, writable: true)?.writable, false)
        XCTAssertEqual(draft.mutationPlan, [])
    }

    private func fixtureManifest() -> NativeUIManifest {
        NativeUIManifest(
            pluginID: "example.plugin",
            hostBuildRange: .init(minimumBuildID: "dsh-locked", maximumBuildID: "dsh-locked"),
            manifestVersion: 1,
            kind: .settingsForm,
            localeResources: [.init(language: "en", namespace: "example", requiredKeys: ["title"])],
            sections: [.init(
                id: "root",
                titleKey: "title",
                fieldIDs: ["enabled", "timeout", "mode", "path", "readOnly", "secret"],
                groupIDs: [],
                order: 0
            )],
            fields: [
                .init(id: "enabled", path: ["enabled"], kind: .toggle, labelKey: "enabled", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 0),
                .init(id: "timeout", path: ["timeoutMs"], kind: .number, labelKey: "timeout", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 1),
                .init(id: "mode", path: ["mode"], kind: .select, labelKey: "mode", helpKey: nil, options: ["fast", "safe"], validationIDs: [], requiredCapabilities: [], order: 2),
                .init(id: "path", path: ["cachePath"], kind: .path, labelKey: "path", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 3),
                .init(id: "readOnly", path: ["hostState"], kind: .readOnly, labelKey: "hostState", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 4),
                .init(id: "secret", path: ["apiKey"], kind: .secret, labelKey: "apiKey", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 5),
            ],
            groups: [],
            order: 0,
            secretRoles: [],
            validations: [],
            actions: [.save, .discard, .reset],
            requiredCapabilities: [],
            integrity: .init(
                algorithm: "sha256",
                digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                sourceCommit: "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e"
            )
        )
    }

    private func fixtureNamespace() -> SettingsNamespaceDTO {
        .init(
            ns: "example",
            schema: .object([:]),
            value: .object([
                "enabled": .bool(false), "timeoutMs": .number(10), "mode": .string("fast"),
                "cachePath": .string("/tmp/cache"), "hostState": .string("ready"),
            ]),
            base: .object([
                "enabled": .bool(false), "timeoutMs": .number(5), "mode": .string("safe"), "cachePath": .string("/tmp/cache"),
            ]),
            user: .object(["timeoutMs": .number(10), "mode": .string("fast")]),
            applies: "host",
            secrets: [],
            revision: 4
        )
    }
}
