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

    func load(using api: SettingsAPI?) {
        guard let api else { phase = .idle; return }
        phase = .loading
        Task {
            do {
                let response = try await api.describe()
                writable = response.writable
                hasDocument = response.hasDocument
                namespaces = response.namespaces
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
    }
}
