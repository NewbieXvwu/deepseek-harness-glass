import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeSettingsStoreTests: XCTestCase {
    func testPermissionAuthorityClearsAfterDescribeFailureOrMissingFacade() async {
        let store = NativeSettingsStore()
        store.load(using: RecordingSettingsAPI(result: .success(.init(
            writable: true,
            hasDocument: true,
            namespaces: [permissionNamespace(value: "workspace-write", revision: 7)]
        ))))
        await eventually { store.phase == .ready }
        XCTAssertEqual(store.permissionPreset.status, .ready)
        XCTAssertTrue(store.permissionPreset.writable)
        XCTAssertEqual(store.permissionPreset.currentValue, "workspace-write")
        XCTAssertFalse(store.namespaces.isEmpty)

        store.load(using: RecordingSettingsAPI(result: .failure(URLError(.cannotConnectToHost))))
        await eventually {
            if case .failed = store.phase { return true }
            return false
        }
        XCTAssertFalse(store.writable)
        XCTAssertFalse(store.hasDocument)
        XCTAssertTrue(store.namespaces.isEmpty)
        XCTAssertEqual(store.permissionPreset.status, .unavailable)
        XCTAssertNil(store.permissionPreset.mutation(selecting: "workspace-write"))

        store.load(using: nil)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.permissionPreset.status, .unavailable)
    }

    func testThemePreferenceSelectionUsesCurrentHostRevisionAndAcceptedNamespace() async throws {
        let initial = themeNamespace(value: "system", revision: 12)
        let accepted = themeNamespace(value: "dark", revision: 13)
        let api = ThemeMutationAPI(initial: initial, accepted: accepted)
        let store = NativeSettingsStore()

        store.load(using: api)
        await eventually { store.themePreference.current == .system }
        try await store.selectThemePreference(.dark, using: api)

        XCTAssertEqual(api.mutations, [[.set(path: ["preference"], value: .string("dark"))]])
        XCTAssertEqual(api.expectedRevisions, [Optional(12)])
        XCTAssertEqual(store.themePreference.current, .dark)
        XCTAssertEqual(store.themePreference.revision, 13)
        XCTAssertFalse(store.isDirty(namespace: "ui-theme"))
    }

    func testAgentPresetDefaultUsesCurrentRevisionAndRejectsBrokenRosterRows() async throws {
        let initial = agentPresetNamespace(value: "standard", revision: 17)
        let accepted = agentPresetNamespace(value: "minimal", revision: 18)
        let api = AgentPresetDefaultMutationAPI(initial: initial, accepted: accepted)
        let store = NativeSettingsStore()
        let selectable = AgentPresetEntryDTO(id: "minimal", trust: "system", isDefault: false, name: "Minimal", description: nil, broken: nil)
        let broken = AgentPresetEntryDTO(id: "broken", trust: "user", isDefault: false, name: nil, description: nil, broken: "Host failure")

        store.load(using: api)
        await eventually { store.agentPresetDefault.current == "standard" }
        try await store.selectAgentPresetDefault(selectable, using: api)
        try await store.selectAgentPresetDefault(broken, using: api)

        XCTAssertEqual(api.mutations, [[.set(path: ["default"], value: .string("minimal"))]])
        XCTAssertEqual(api.expectedRevisions, [Optional(17)])
        XCTAssertEqual(store.agentPresetDefault.current, "minimal")
        XCTAssertEqual(store.agentPresetDefault.revision, 18)
        XCTAssertFalse(store.isDirty(namespace: "agent-presets"))
    }

    func testPluginCardSaveUsesOneCurrentRevisionFencedHostMutation() async throws {
        let initial = shellNamespace(timeout: 60_000, outputCap: 64_000, revision: 12)
        let accepted = shellNamespace(timeout: 9_000, outputCap: 1_024, revision: 13)
        let api = PluginMutationAPI(initial: initial, accepted: accepted)
        let store = NativeSettingsStore()
        let timeout = NativePluginCardField("timeoutMs", kind: .number)
        let outputCap = NativePluginCardField("maxOutputBytes", kind: .number)
        var draft = NativePluginCardDraft(namespace: initial, fields: [timeout, outputCap])
        draft.stage("9000", for: timeout)
        draft.stage("1024", for: outputCap)

        store.load(using: api)
        await eventually { store.namespaces.first?.revision == 12 }
        let saved = try await store.savePluginCardDraft(draft, using: api)
        XCTAssertTrue(saved)

        XCTAssertEqual(api.expectedRevisions, [Optional(12)])
        XCTAssertEqual(api.mutations, [[
            .set(path: ["maxOutputBytes"], value: .number(1024)),
            .set(path: ["timeoutMs"], value: .number(9000)),
        ]])
        XCTAssertEqual(store.namespaces.first, accepted)

        var invalid = NativePluginCardDraft(namespace: accepted, fields: [timeout])
        invalid.stage("soon", for: timeout)
        let invalidSaveAccepted = try await store.savePluginCardDraft(invalid, using: api)
        XCTAssertFalse(invalidSaveAccepted)
        XCTAssertEqual(api.expectedRevisions, [Optional(12)])
    }

    func testDiscoveredModelAdoptionWritesOnlyHostCandidatesWithCurrentRevision() async throws {
        let existing = JSONValue.object([
            "id": .string("configured"), "contextWindow": .number(777), "futureProfile": .string("preserve"),
        ])
        let initial = modelProviderNamespace(models: [existing], revision: 31)
        let adopted = JSONValue.object([
            "id": .string("fresh"), "name": .string("Fresh"),
            "contextWindow": .number(128_000), "maxTokens": .number(8_192),
        ])
        let accepted = modelProviderNamespace(models: [existing, adopted], revision: 32)
        let api = ModelDiscoveryMutationAPI(initial: initial, accepted: accepted)
        let store = NativeSettingsStore()
        let provider = LLMProviderDTO(
            provider: "provider", displayName: "Provider", settingsNs: "provider-settings",
            settingsPath: [], active: true, declared: true
        )
        let candidates = [
            LLMDiscoveredModelDTO(id: "configured", name: "Provider default", contextWindow: 4_096, maxTokens: 1_024),
            LLMDiscoveredModelDTO(id: "fresh", name: "Fresh", contextWindow: 128_000, maxTokens: 8_192),
        ]

        store.load(using: api)
        await eventually { store.namespaces.first?.revision == 31 }
        let initiallySelected = NativeDiscoveredModelSelection.initiallySelectedIDs(
            candidates: candidates,
            existingModels: NativeDiscoveredModelSelection.models(in: initial, providerPath: [])
        )
        XCTAssertEqual(initiallySelected, ["fresh"])
        let adoptedModels = try await store.adoptDiscoveredModels(
            candidates,
            selectedIDs: initiallySelected.union(["untrusted-id"]),
            for: provider,
            using: api
        )
        XCTAssertTrue(adoptedModels)

        XCTAssertEqual(api.expectedRevisions, [Optional(31)])
        XCTAssertEqual(api.mutations, [[.set(path: ["models"], value: .array([existing, adopted]))]])
        XCTAssertEqual(store.namespaces.first, accepted)
        XCTAssertFalse(store.isDirty(namespace: "provider-settings"))
    }

    func testSecretSettingOperationCannotEnterDraftState() {
        let namespace = SettingsNamespaceDTO(
            ns: "provider",
            schema: .object([:]),
            value: .object([:]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [.init(path: ["apiKey"], set: true)],
            revision: 1
        )
        let store = NativeSettingsStore()

        XCTAssertFalse(store.stage(
            namespace: namespace,
            operation: .set(path: ["apiKey"], value: .string("must-not-be-retained"))
        ))
        XCTAssertFalse(store.isDirty(namespace: namespace.ns))
        XCTAssertTrue(store.drafts.isEmpty)
        XCTAssertTrue(store.stage(
            namespace: namespace,
            operation: .set(path: ["displayName"], value: .string("safe-draft"))
        ))
        XCTAssertEqual(store.drafts[namespace.ns]?.operation, .set(path: ["displayName"], value: .string("safe-draft")))
    }

    func testSettingsRootNavigationUsesOnlyLockedOfficialLocaleValues() {
        XCTAssertEqual(NativeSettingsRoot.SectionID.general.title, OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-general", key: "general.nav", language: "en"))
        XCTAssertEqual(NativeSettingsRoot.SectionID.models.title, OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: "nav", language: "en"))
        XCTAssertEqual(NativeSettingsRoot.SectionID.plugins.title, OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-plugins", key: "nav", language: "en"))
        XCTAssertEqual(NativeSettingsRoot.SectionID.agentPresets.title, OfficialUISpec.LocaleCatalog.value(namespace: "ui-agent-preset", key: "nav", language: "en"))
    }

    func testShellSettingsOpenAndCloseUseTypedStoreWithoutInventingHostAuthority() {
        let store = NativeSettingsStore()
        let presentation = NativeShellPresentation(mode: .conversation, settingsStore: store)

        presentation.openSettings()
        XCTAssertTrue(presentation.settingsPresented)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(store.namespaces.isEmpty)

        presentation.closeSettings()
        XCTAssertFalse(presentation.settingsPresented)
    }

    func testDiscardDraftRemovesOnlyLocalIntentWithoutChangingHostNamespace() {
        let namespace = permissionNamespace(value: "workspace-write", revision: 7)
        let store = NativeSettingsStore()
        let operation = SettingsPathOperationDTO.set(
            path: ["defaultPreset"],
            value: .string("danger-full-access")
        )

        XCTAssertTrue(store.stage(namespace: namespace, operation: operation))
        store.discardDraft(namespace: namespace.ns)

        XCTAssertFalse(store.isDirty(namespace: namespace.ns))
        XCTAssertNil(store.drafts[namespace.ns])
        XCTAssertEqual(namespace.value, .object(["defaultPreset": .string("workspace-write")]))
    }

    func testDescribeFailureClearsStaleAuthorityButRetainsNonSecretDraftForReconnect() async {
        let original = permissionNamespace(value: "workspace-write", revision: 7)
        let store = NativeSettingsStore()
        let available = RecordingSettingsAPI(result: .success(.init(writable: true, hasDocument: true, namespaces: [original])))
        let unavailable = FailingSettingsAPI()
        let operation = SettingsPathOperationDTO.set(
            path: ["defaultPreset"],
            value: .string("danger-full-access")
        )

        store.load(using: available)
        await eventually { store.namespaces.first?.revision == 7 }
        XCTAssertTrue(store.stage(namespace: original, operation: operation))
        store.load(using: unavailable)
        await eventually {
            if case .failed = store.phase { return true }
            return false
        }

        XCTAssertTrue(store.namespaces.isEmpty)
        XCTAssertEqual(store.permissionPreset.status, .unavailable)
        XCTAssertEqual(store.drafts["permission"]?.operation, operation)
        XCTAssertTrue(store.isDirty(namespace: "permission"))
    }

    func testSupersededDescribeCannotReviveOldSettingsAuthority() async {
        let api = DelayedFirstDescribeSettingsAPI(
            old: .init(writable: true, hasDocument: true, namespaces: [permissionNamespace(value: "workspace-write", revision: 7)]),
            current: .init(writable: true, hasDocument: true, namespaces: [permissionNamespace(value: "danger-full-access", revision: 8)])
        )
        let store = NativeSettingsStore()

        store.load(using: api)
        await eventually { api.describeCount == 1 }
        store.load(using: api)
        await eventually { store.namespaces.first?.revision == 8 }
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(store.namespaces.first?.revision, 8)
        XCTAssertEqual(store.permissionPreset.currentValue, "danger-full-access")
        XCTAssertEqual(store.phase, .ready)
    }

    func testRevisionConflictRetainsDraftAcrossRemoteRefreshAndRetriesWithLatestHostRevision() async throws {
        let original = permissionNamespace(value: "workspace-write", revision: 7)
        let remote = permissionNamespace(value: "workspace-write", revision: 8)
        let accepted = permissionNamespace(value: "danger-full-access", revision: 9)
        let api = ConflictThenAcceptingSettingsAPI(
            describes: [
                .init(writable: true, hasDocument: true, namespaces: [original]),
                .init(writable: true, hasDocument: true, namespaces: [remote]),
            ],
            accepted: accepted
        )
        let store = NativeSettingsStore()
        let operation = SettingsPathOperationDTO.set(
            path: ["defaultPreset"],
            value: .string("danger-full-access")
        )

        store.load(using: api)
        await eventually { store.namespaces.first?.revision == 7 }
        XCTAssertTrue(store.stage(namespace: original, operation: operation))
        XCTAssertTrue(store.isDirty(namespace: "permission"))

        do {
            try await store.saveDraft(namespace: "permission", using: api)
            XCTFail("an old Host revision must reject the first save")
        } catch {
            // The fake represents a second client committing revision 8 first.
        }
        XCTAssertEqual(api.expectedRevisions, [Optional(7)])
        XCTAssertEqual(store.namespaces.first?.revision, 7, "a rejected write must not invent a local namespace revision")
        XCTAssertEqual(store.drafts["permission"]?.operation, operation)

        store.load(using: api)
        await eventually { store.namespaces.first?.revision == 8 }
        XCTAssertEqual(store.drafts["permission"]?.operation, operation, "remote invalidation must preserve the correct local draft for repair or retry")

        try await store.saveDraft(namespace: "permission", using: api)
        XCTAssertEqual(api.expectedRevisions, [Optional(7), Optional(8)])
        XCTAssertEqual(store.namespaces.first, accepted)
        XCTAssertFalse(store.isDirty(namespace: "permission"), "only an accepted Host mutation may clear a staged draft")
    }

    private func eventually(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition was not met before timeout")
    }

    private func shellNamespace(timeout: Double, outputCap: Double, revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "shell",
            schema: .object([:]),
            value: .object(["timeoutMs": .number(timeout), "maxOutputBytes": .number(outputCap)]),
            base: .object(["timeoutMs": .number(60_000), "maxOutputBytes": .number(64_000)]),
            user: nil,
            applies: "live",
            secrets: [],
            revision: revision
        )
    }

    private func modelProviderNamespace(models: [JSONValue], revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "provider-settings",
            schema: .object([:]),
            value: .object(["models": .array(models)]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [],
            revision: revision
        )
    }

    private func themeNamespace(value: String, revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "ui-theme",
            schema: .object([:]),
            value: .object(["preference": .string(value)]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [],
            revision: revision
        )
    }

    private func agentPresetNamespace(value: String, revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "agent-presets",
            schema: .object([:]),
            value: .object(["default": .string(value)]),
            base: nil,
            user: nil,
            applies: "new-sessions",
            secrets: [],
            revision: revision
        )
    }

    private func permissionNamespace(value: String, revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "permission",
            schema: .object([
                "uid": .number(6),
                "refs": .object([
                    "1": .object(["type": .string("const"), "value": .string("read-only")]),
                    "2": .object(["type": .string("const"), "value": .string("workspace-write")]),
                    "4": .object(["type": .string("union"), "list": .array([.number(1), .number(2)])]),
                    "6": .object(["type": .string("object"), "dict": .object(["defaultPreset": .number(4)])]),
                ]),
            ]),
            value: .object(["defaultPreset": .string(value)]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [],
            revision: revision
        )
    }

    @MainActor
    private final class FailingSettingsAPI: NativeSettingsAPI {
        func describe() async throws -> SettingsDescribeResponse { throw URLError(.notConnectedToInternet) }
        func mutate(namespace _: String, operations _: [SettingsPathOperationDTO], expectedRevision _: Int?) async throws -> SettingsNamespaceDTO {
            throw URLError(.notConnectedToInternet)
        }
    }

    @MainActor
    private final class DelayedFirstDescribeSettingsAPI: NativeSettingsAPI {
        private let old: SettingsDescribeResponse
        private let current: SettingsDescribeResponse
        private(set) var describeCount = 0

        init(old: SettingsDescribeResponse, current: SettingsDescribeResponse) {
            self.old = old
            self.current = current
        }

        func describe() async throws -> SettingsDescribeResponse {
            describeCount += 1
            if describeCount == 1 {
                try? await Task.sleep(for: .milliseconds(150))
                return old
            }
            return current
        }

        func mutate(
            namespace _: String,
            operations _: [SettingsPathOperationDTO],
            expectedRevision _: Int?
        ) async throws -> SettingsNamespaceDTO {
            throw URLError(.cannotWriteToFile)
        }
    }

    @MainActor
    private final class ConflictThenAcceptingSettingsAPI: NativeSettingsAPI {
        private var describes: [SettingsDescribeResponse]
        private let accepted: SettingsNamespaceDTO
        private(set) var expectedRevisions: [Int?] = []
        private var mutationCount = 0

        init(describes: [SettingsDescribeResponse], accepted: SettingsNamespaceDTO) {
            self.describes = describes
            self.accepted = accepted
        }

        func describe() async throws -> SettingsDescribeResponse {
            guard !describes.isEmpty else { throw URLError(.badServerResponse) }
            return describes.removeFirst()
        }

        func mutate(
            namespace _: String,
            operations _: [SettingsPathOperationDTO],
            expectedRevision: Int?
        ) async throws -> SettingsNamespaceDTO {
            expectedRevisions.append(expectedRevision)
            mutationCount += 1
            if mutationCount == 1 { throw URLError(.cannotWriteToFile) }
            return accepted
        }
    }

    @MainActor
    private final class PluginMutationAPI: NativeSettingsAPI {
        private let initial: SettingsNamespaceDTO
        private let accepted: SettingsNamespaceDTO
        private(set) var mutations: [[SettingsPathOperationDTO]] = []
        private(set) var expectedRevisions: [Int?] = []

        init(initial: SettingsNamespaceDTO, accepted: SettingsNamespaceDTO) {
            self.initial = initial
            self.accepted = accepted
        }

        func describe() async throws -> SettingsDescribeResponse {
            .init(writable: true, hasDocument: true, namespaces: [initial])
        }

        func mutate(
            namespace: String,
            operations: [SettingsPathOperationDTO],
            expectedRevision: Int?
        ) async throws -> SettingsNamespaceDTO {
            XCTAssertEqual(namespace, "shell")
            mutations.append(operations)
            expectedRevisions.append(expectedRevision)
            return accepted
        }
    }

    @MainActor
    private final class AgentPresetDefaultMutationAPI: NativeSettingsAPI {
        private let initial: SettingsNamespaceDTO
        private let accepted: SettingsNamespaceDTO
        private(set) var mutations: [[SettingsPathOperationDTO]] = []
        private(set) var expectedRevisions: [Int?] = []

        init(initial: SettingsNamespaceDTO, accepted: SettingsNamespaceDTO) {
            self.initial = initial
            self.accepted = accepted
        }

        func describe() async throws -> SettingsDescribeResponse {
            .init(writable: true, hasDocument: true, namespaces: [initial])
        }

        func mutate(
            namespace: String,
            operations: [SettingsPathOperationDTO],
            expectedRevision: Int?
        ) async throws -> SettingsNamespaceDTO {
            XCTAssertEqual(namespace, "agent-presets")
            mutations.append(operations)
            expectedRevisions.append(expectedRevision)
            return accepted
        }
    }

    @MainActor
    private final class ModelDiscoveryMutationAPI: NativeSettingsAPI {
        private let initial: SettingsNamespaceDTO
        private let accepted: SettingsNamespaceDTO
        private(set) var mutations: [[SettingsPathOperationDTO]] = []
        private(set) var expectedRevisions: [Int?] = []

        init(initial: SettingsNamespaceDTO, accepted: SettingsNamespaceDTO) {
            self.initial = initial
            self.accepted = accepted
        }

        func describe() async throws -> SettingsDescribeResponse {
            .init(writable: true, hasDocument: true, namespaces: [initial])
        }

        func mutate(
            namespace: String,
            operations: [SettingsPathOperationDTO],
            expectedRevision: Int?
        ) async throws -> SettingsNamespaceDTO {
            XCTAssertEqual(namespace, "provider-settings")
            mutations.append(operations)
            expectedRevisions.append(expectedRevision)
            return accepted
        }
    }

    @MainActor
    private final class ThemeMutationAPI: NativeSettingsAPI {
        private let initial: SettingsNamespaceDTO
        private let accepted: SettingsNamespaceDTO
        private(set) var mutations: [[SettingsPathOperationDTO]] = []
        private(set) var expectedRevisions: [Int?] = []

        init(initial: SettingsNamespaceDTO, accepted: SettingsNamespaceDTO) {
            self.initial = initial
            self.accepted = accepted
        }

        func describe() async throws -> SettingsDescribeResponse {
            .init(writable: true, hasDocument: true, namespaces: [initial])
        }

        func mutate(
            namespace: String,
            operations: [SettingsPathOperationDTO],
            expectedRevision: Int?
        ) async throws -> SettingsNamespaceDTO {
            XCTAssertEqual(namespace, "ui-theme")
            mutations.append(operations)
            expectedRevisions.append(expectedRevision)
            return accepted
        }
    }

    @MainActor
    private final class RecordingSettingsAPI: NativeSettingsAPI {
        let result: Result<SettingsDescribeResponse, Error>

        init(result: Result<SettingsDescribeResponse, Error>) {
            self.result = result
        }

        func describe() async throws -> SettingsDescribeResponse {
            try result.get()
        }

        func mutate(
            namespace _: String,
            operations _: [SettingsPathOperationDTO],
            expectedRevision _: Int?
        ) async throws -> SettingsNamespaceDTO {
            throw URLError(.cannotConnectToHost)
        }
    }
}
