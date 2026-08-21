import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Typed settings boundary for the native feature. Production continues to use
/// the verified `SettingsAPI`; tests can inject success/failure authority without
/// assembling wire envelopes or raw JSON.
@MainActor
protocol NativeSettingsAPI: Sendable {
    func describe() async throws -> SettingsDescribeResponse
    func mutate(
        namespace: String,
        operations: [SettingsPathOperationDTO],
        expectedRevision: Int?
    ) async throws -> SettingsNamespaceDTO
}

extension SettingsAPI: NativeSettingsAPI {}

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
            clearAuthority(phase: .idle)
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
                self?.phase = .ready
            } catch {
                guard !Task.isCancelled, self?.authorityGeneration == generation else { return }
                self?.clearAuthority(phase: .failed(error.localizedDescription))
            }
        }
    }

    /// Records a caller-selected mutation without treating it as durable Host
    /// state. A newer remote descriptor may change its revision, but must not
    /// silently erase a user draft after a conflict.
    func stage(namespace: SettingsNamespaceDTO, operation: SettingsPathOperationDTO) {
        drafts[namespace.ns] = Draft(namespace: namespace.ns, operation: operation)
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
        else { return }
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
    }

    func mutate(
        namespace: SettingsNamespaceDTO,
        operation: SettingsPathOperationDTO,
        using api: (any NativeSettingsAPI)?
    ) async throws {
        stage(namespace: namespace, operation: operation)
        try await saveDraft(namespace: namespace.ns, using: api)
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

    private func clearAuthority(phase: Phase) {
        writable = false
        hasDocument = false
        namespaces = []
        drafts = [:]
        permissionPreset = .init(
            status: .unavailable,
            writable: false,
            currentValue: "",
            options: [],
            revision: nil
        )
        self.phase = phase
    }
}
