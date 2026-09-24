import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Host-authoritative settings projection. Secret values never enter this store:
/// `settings.describe` returns only redacted values plus write-only slot state.
@MainActor
final class NativeSettingsStore: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }

    /// A user-authored settings intent remains separate from the last complete
    /// Host namespace. It contains only a path operation and never reads secret
    /// values back into UI state.
    struct Draft: Equatable {
        let namespace: String
        let operation: SettingsPathOperationDTO
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var writable = false
    @Published private(set) var hasDocument = false
    @Published private(set) var namespaces: [SettingsNamespaceDTO] = []
    @Published private(set) var drafts: [String: Draft] = [:]
    @Published var lastMutationError: String?
    /// Host-derived `permission.defaultPreset` state. It is unavailable or
    /// malformed by construction when the descriptor cannot safely advertise a
    /// writable option; no UI-side preset list is invented.
    @Published private(set) var permissionPreset = CorePermissionPresetState(
        status: .unavailable,
        writable: false,
        currentValue: "",
        options: [],
        revision: nil
    )
    /// Host-derived official `ui-theme.preference` state. The current value is
    /// the persisted preference rather than a locally resolved appearance.
    @Published private(set) var themePreference = CoreThemePreferenceState(
        status: .unavailable,
        writable: false,
        current: nil,
        revision: nil
    )
    /// Host-derived `agent-presets.default` state. Choices remain sourced from
    /// `agentPreset.list`; settings only owns the persisted default field.
    @Published private(set) var agentPresetDefault = CoreAgentPresetDefaultState(
        status: .unavailable,
        writable: false,
        current: nil,
        revision: nil
    )

    private var loadTask: Task<Void, Never>?
    private var authorityGeneration = 0

    deinit {
        loadTask?.cancel()
    }

    func load(using api: (any NativeSettingsAPI)?) {
        loadTask?.cancel()
        authorityGeneration &+= 1
        let generation = authorityGeneration
        guard let api else {
            clearAuthority(phase: .idle, clearingDrafts: true)
            return
        }
        phase = .loading
        loadTask = Task { [weak self] in
            do {
                let response = try await api.describe()
                guard !Task.isCancelled, self?.authorityGeneration == generation else { return }
                self?.writable = response.writable
                self?.hasDocument = response.hasDocument
                self?.namespaces = response.namespaces
                self?.permissionPreset = PermissionPresetProjection.state(
                    namespaces: response.namespaces,
                    writable: response.writable
                )
                self?.themePreference = ThemePreferenceProjection.state(
                    namespaces: response.namespaces,
                    writable: response.writable
                )
                self?.agentPresetDefault = AgentPresetDefaultProjection.state(
                    namespaces: response.namespaces,
                    writable: response.writable
                )
                self?.phase = .ready
            } catch {
                guard !Task.isCancelled, self?.authorityGeneration == generation else { return }
                self?.clearAuthority(phase: .failed(error.localizedDescription), clearingDrafts: false)
            }
        }
    }

    /// Records a caller-selected mutation without treating it as durable Host
    /// state. A newer remote descriptor may change its revision, but must not
    /// silently erase a user draft after a conflict. Write-only secret slots use
    /// the dedicated credentials boundary and are never retained in this store.
    @discardableResult
    func stage(namespace: SettingsNamespaceDTO, operation: SettingsPathOperationDTO) -> Bool {
        guard !namespace.secrets.contains(where: { $0.path == operation.path }) else { return false }
        drafts[namespace.ns] = Draft(namespace: namespace.ns, operation: operation)
        return true
    }

    func discardDraft(namespace: String) {
        drafts[namespace] = nil
    }

    func isDirty(namespace: String) -> Bool {
        drafts[namespace] != nil
    }

    /// Sends the staged intent using the newest complete namespace revision. A
    /// rejected mutation deliberately leaves the draft and current Host snapshot
    /// intact so the caller can refresh, correct, discard, or retry.
    func saveDraft(namespace: String, using api: (any NativeSettingsAPI)?) async throws {
        guard let api else { throw URLError(.notConnectedToInternet) }
        guard let draft = drafts[namespace],
              let current = namespaces.first(where: { $0.ns == namespace })
        else {
            lastMutationError = "settings namespace not found: \(namespace)"
            return
        }
        let updated = try await api.mutate(
            namespace: namespace,
            operations: [draft.operation],
            expectedRevision: current.revision
        )
        guard let index = namespaces.firstIndex(where: { $0.ns == updated.ns }) else { return }
        namespaces[index] = updated
        drafts[namespace] = nil
        permissionPreset = PermissionPresetProjection.state(
            namespaces: namespaces,
            writable: writable
        )
        themePreference = ThemePreferenceProjection.state(
            namespaces: namespaces,
            writable: writable
        )
        agentPresetDefault = AgentPresetDefaultProjection.state(
            namespaces: namespaces,
            writable: writable
        )
    }

    func mutate(
        namespace: SettingsNamespaceDTO,
        operation: SettingsPathOperationDTO,
        using api: (any NativeSettingsAPI)?
    ) async throws {
        guard stage(namespace: namespace, operation: operation) else { return }
        try await saveDraft(namespace: namespace.ns, using: api)
    }

    /// Commits a reviewed card's complete non-secret plan as one revision-fenced
    /// Host mutation. An invalid draft returns false; a rejected mutation leaves
    /// the card itself untouched for correction and does not invent authority.
    @discardableResult
    func savePluginCardDraft(_ draft: NativePluginCardDraft, using api: (any NativeSettingsAPI)?) async throws -> Bool {
        guard let api,
              let operations = draft.mutationPlan,
              !operations.isEmpty,
              let current = namespaces.first(where: { $0.ns == draft.namespace.ns })
        else { return false }
        let updated = try await api.mutate(
            namespace: current.ns,
            operations: operations,
            expectedRevision: current.revision
        )
        guard let index = namespaces.firstIndex(where: { $0.ns == updated.ns }) else { return false }
        namespaces[index] = updated
        permissionPreset = PermissionPresetProjection.state(
            namespaces: namespaces,
            writable: writable
        )
        themePreference = ThemePreferenceProjection.state(
            namespaces: namespaces,
            writable: writable
        )
        agentPresetDefault = AgentPresetDefaultProjection.state(
            namespaces: namespaces,
            writable: writable
        )
        return true
    }

    /// Adopts only IDs advertised by the latest Host discovery response. Existing
    /// model rows remain byte-for-byte intact, so a user-tuned capacity always
    /// wins over a provider candidate. The resulting whole models value travels
    /// through the normal revision-fenced draft path and is never published until
    /// Host returns an updated namespace.
    @discardableResult
    func adoptDiscoveredModels(
        _ candidates: [LLMDiscoveredModelDTO],
        selectedIDs: Set<String>,
        for provider: LLMProviderDTO,
        using api: (any NativeSettingsAPI)?
    ) async throws -> Bool {
        guard let namespace = namespaces.first(where: { $0.ns == provider.settingsNs }),
              let operation = NativeDiscoveredModelSelection.operation(
                  candidates: candidates,
                  selectedIDs: selectedIDs,
                  namespace: namespace,
                  providerPath: provider.settingsPath
              )
        else { return false }
        try await mutate(namespace: namespace, operation: operation, using: api)
        return true
    }

    /// Writes only the official `ui-theme.preference` enum advertised by the
    /// latest Host snapshot. Unknown/raw strings cannot reach transport.
    func selectThemePreference(_ preference: CoreThemePreference, using api: (any NativeSettingsAPI)?) async throws {
        guard let namespace = namespaces.first(where: { $0.ns == ThemePreferenceProjection.namespace }),
              let operation = themePreference.mutation(selecting: preference)
        else { return }
        try await mutate(namespace: namespace, operation: operation, using: api)
    }

    /// Writes only a current Host roster row that can compose a new session to
    /// the official `agent-presets.default` field. The Host's returned namespace
    /// replaces the local settings authority after the revision-fenced mutation.
    func selectAgentPresetDefault(_ preset: AgentPresetEntryDTO, using api: (any NativeSettingsAPI)?) async throws {
        guard preset.broken == nil,
              let namespace = namespaces.first(where: { $0.ns == AgentPresetDefaultProjection.namespace }),
              let operation = agentPresetDefault.mutation(selecting: preset.id)
        else { return }
        try await mutate(namespace: namespace, operation: operation, using: api)
    }

    /// Writes only an option advertised by the latest Host permission schema,
    /// with the namespace revision carried by `mutate`. Callers cannot route an
    /// arbitrary raw preset string to transport.
    func selectPermissionPreset(_ preset: String, using api: (any NativeSettingsAPI)?) async throws {
        guard let namespace = namespaces.first(where: { $0.ns == PermissionPresetProjection.namespace }),
              let operation = permissionPreset.mutation(selecting: preset)
        else { return }
        try await mutate(namespace: namespace, operation: operation, using: api)
    }

    private func clearAuthority(phase: Phase, clearingDrafts: Bool) {
        writable = false
        hasDocument = false
        namespaces = []
        if clearingDrafts { drafts = [:] }
        permissionPreset = .init(
            status: .unavailable,
            writable: false,
            currentValue: "",
            options: [],
            revision: nil
        )
        themePreference = .init(
            status: .unavailable,
            writable: false,
            current: nil,
            revision: nil
        )
        agentPresetDefault = .init(
            status: .unavailable,
            writable: false,
            current: nil,
            revision: nil
        )
        self.phase = phase
    }
}
