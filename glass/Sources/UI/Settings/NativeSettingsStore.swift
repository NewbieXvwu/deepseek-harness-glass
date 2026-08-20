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

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var writable = false
    @Published private(set) var hasDocument = false
    @Published private(set) var namespaces: [SettingsNamespaceDTO] = []
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

    func load(using api: (any NativeSettingsAPI)?) {
        guard let api else {
            clearAuthority(phase: .idle)
            return
        }
        phase = .loading
        Task {
            do {
                let response = try await api.describe()
                writable = response.writable
                hasDocument = response.hasDocument
                namespaces = response.namespaces
                permissionPreset = PermissionPresetProjection.state(
                    namespaces: response.namespaces,
                    writable: response.writable
                )
                phase = .ready
            } catch {
                clearAuthority(phase: .failed(error.localizedDescription))
            }
        }
    }

    func mutate(
        namespace: SettingsNamespaceDTO,
        operation: SettingsPathOperationDTO,
        using api: (any NativeSettingsAPI)?
    ) async throws {
        guard let api else { throw URLError(.notConnectedToInternet) }
        let updated = try await api.mutate(
            namespace: namespace.ns,
            operations: [operation],
            expectedRevision: namespace.revision
        )
        guard let index = namespaces.firstIndex(where: { $0.ns == updated.ns }) else { return }
        namespaces[index] = updated
        permissionPreset = PermissionPresetProjection.state(
            namespaces: namespaces,
            writable: writable
        )
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
