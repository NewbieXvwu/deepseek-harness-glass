import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Renderer-safe projection of the Host-owned per-session `session.models`
/// directory. It is refreshed by `NativeSessionStore.open` before history/mux
/// authority is installed; a failure row remains non-selectable presentation
/// data and never becomes a synthetic available model.
struct CoreSessionModelDirectory: Equatable {
    struct Selection: Equatable {
        let provider: String
        let model: String
        let reasoningEffort: String?
    }

    struct ReasoningEffort: Equatable {
        let id: String
        let name: String
        let description: String?
    }

    struct Model: Equatable, Identifiable {
        let id: String
        let name: String
        let description: String?
        let reasoningEfforts: [ReasoningEffort]
        let defaultReasoningEffort: String?
    }

    struct ProviderGroup: Equatable, Identifiable {
        let id: String
        let name: String
        let models: [Model]
    }

    struct Failure: Equatable, Identifiable {
        let id: String
        let name: String
        let message: String
    }

    let current: Selection
    let routable: Bool
    let groups: [ProviderGroup]
    let failures: [Failure]

    init(catalog: RemoteModelCatalog, current: RemoteModelSelection) {
        self.current = .init(
            provider: current.provider,
            model: current.model,
            reasoningEffort: current.reasoningEffort
        )
        routable = catalog.routableProviders.contains(current.provider)
        groups = catalog.groups.map { group in
            .init(
                id: group.id,
                name: group.name,
                models: group.models.map { model in
                    .init(
                        id: model.id,
                        name: model.name,
                        description: model.description,
                        reasoningEfforts: model.reasoning?.efforts.map {
                            .init(id: $0.id, name: $0.name, description: $0.description)
                        } ?? [],
                        defaultReasoningEffort: model.reasoning?.defaultEffort
                    )
                }
            )
        }
        failures = catalog.failures.map { .init(id: $0.id, name: $0.name, message: $0.message) }
    }

    init(response: SessionModelsResponse) {
        current = .init(
            provider: response.current.provider,
            model: response.current.model,
            reasoningEffort: response.current.reasoningEffort
        )
        routable = response.routable
        groups = response.groups.map { group in
            .init(
                id: group.id,
                name: group.name,
                models: group.models.map { model in
                    .init(
                        id: model.id,
                        name: model.name,
                        description: model.description,
                        reasoningEfforts: model.reasoning?.efforts.map {
                            .init(id: $0.id, name: $0.name, description: $0.description)
                        } ?? [],
                        defaultReasoningEffort: model.reasoning?.defaultEffort
                    )
                }
            )
        }
        failures = response.failures.map { .init(id: $0.id, name: $0.name, message: $0.message) }
    }

    /// A model may be submitted only when it is advertised in a loaded provider
    /// group. Catalog failures remain visible but do not create a fallback route.
    func contains(provider: String, model: String) -> Bool {
        groups.contains { group in
            group.id == provider && group.models.contains { $0.id == model }
        }
    }

    /// A native chooser only emits selections backed by the complete Host
    /// directory. When effort is supplied, it must belong to that advertised
    /// model; an unknown effort never becomes a client-side route.
    func contains(provider: String, model: String, reasoningEffort: String?) -> Bool {
        guard let selectedModel = groups.first(where: { $0.id == provider })?.models.first(where: { $0.id == model }) else {
            return false
        }
        return reasoningEffort == nil || selectedModel.reasoningEfforts.contains(where: { $0.id == reasoningEffort })
    }

    /// RC8 directory select only replaces `current` after `session.selectModel`
    /// returns a Host-confirmed selection. Provider groups/failures remain the
    /// last complete directory snapshot and are never edited optimistically.
    func applying(_ selected: SessionModelSelectionDTO) -> CoreSessionModelDirectory {
        .init(
            current: .init(
                provider: selected.provider,
                model: selected.model,
                reasoningEffort: selected.reasoningEffort
            ),
            routable: true,
            groups: groups,
            failures: failures
        )
    }

    func applying(_ selected: RemoteModelSelection) -> CoreSessionModelDirectory {
        .init(
            current: .init(
                provider: selected.provider,
                model: selected.model,
                reasoningEffort: selected.reasoningEffort
            ),
            routable: true,
            groups: groups,
            failures: failures
        )
    }

    private init(
        current: Selection,
        routable: Bool,
        groups: [ProviderGroup],
        failures: [Failure]
    ) {
        self.current = current
        self.routable = routable
        self.groups = groups
        self.failures = failures
    }
}
