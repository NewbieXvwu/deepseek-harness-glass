import Combine

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Host-authoritative, readback-safe credentials state. Secret text exists only
/// as a method argument during `set`; the observable store retains no literal.
@MainActor
final class NativeCredentialStore: ObservableObject {
    @Published private(set) var views: [String: CredentialViewDTO] = [:]
    private var refreshGeneration = 0

    func view(for reference: String) -> CredentialViewDTO? {
        views[reference]
    }

    func refresh(refs: [String], using api: (any NativeCredentialAPI)?) async {
        refreshGeneration &+= 1
        let currentGeneration = refreshGeneration
        guard let api else { return }
        do {
            let response = try await api.describe(refs: refs)
            guard refreshGeneration == currentGeneration else { return }
            let requested = Set(refs)
            // A Host may return extra views for a wider request batch. Only the
            // requested refs are promoted, and previously loaded views for other
            // refs are preserved: a narrow refresh must not wipe sibling cards.
            var merged = views
            for (key, view) in response.credentials where requested.contains(key) {
                merged[key] = view
            }
            views = merged
        } catch {
            guard refreshGeneration == currentGeneration else { return }
            // Keep the most recent Host-safe facts; a read failure must not
            // manufacture a configured/unconfigured credential status.
        }
    }

    /// The supplied literal is sent once to the typed Host facade, then dropped.
    /// Success is defined by a fresh Host `configured` view for the same ref.
    @discardableResult
    func set(reference: String, value: String, using api: (any NativeCredentialAPI)?) async -> Bool {
        guard let api, !reference.isEmpty, !value.isEmpty else { return false }
        do {
            _ = try await api.set(ref: reference, value: value)
        } catch {
            return false
        }
        await refresh(refs: [reference], using: api)
        return views[reference]?.configured == true
    }

    @discardableResult
    func unset(reference: String, using api: (any NativeCredentialAPI)?) async -> Bool {
        guard let api, !reference.isEmpty else { return false }
        do {
            _ = try await api.unset(ref: reference)
        } catch {
            return false
        }
        await refresh(refs: [reference], using: api)
        return views[reference]?.configured == false
    }
}
