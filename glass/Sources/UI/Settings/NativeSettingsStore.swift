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

    func load(using api: SettingsAPI?) {
        guard let api else { phase = .idle; return }
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
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func mutate(
        namespace: SettingsNamespaceDTO,
        operation: SettingsPathOperationDTO,
        using api: SettingsAPI?
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
    func selectPermissionPreset(_ preset: String, using api: SettingsAPI?) async throws {
        guard let namespace = namespaces.first(where: { $0.ns == PermissionPresetProjection.namespace }),
              let operation = permissionPreset.mutation(selecting: preset)
        else { return }
        try await mutate(namespace: namespace, operation: operation, using: api)
    }
}
