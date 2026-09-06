import Foundation

protocol ModelCatalogSource: Sendable {
    func modelCatalog() async throws -> RemoteModelCatalog
}

extension SessionController: ModelCatalogSource {}

/// Host-wide owner of the rc.1 `session/modelCatalog` snapshot. Session stores
/// consume a catalog to build per-session projections but never retain the
/// Host-wide wire model themselves.
actor ModelCatalogRepository {
    private let controller: any ModelCatalogSource
    private var cached: RemoteModelCatalog?
    private var loadTask: Task<RemoteModelCatalog, Error>?
    private var generation: UInt = 0

    init(controller: any ModelCatalogSource) {
        self.controller = controller
    }

    func catalog(forceReload: Bool = false) async throws -> RemoteModelCatalog {
        if !forceReload, let cached { return cached }
        if !forceReload, let loadTask { return try await loadTask.value }

        generation &+= 1
        let requestGeneration = generation
        let controller = self.controller
        let task = Task { try await controller.modelCatalog() }
        loadTask = task
        do {
            let catalog = try await task.value
            guard generation == requestGeneration else { return catalog }
            loadTask = nil
            cached = catalog
            return catalog
        } catch {
            if generation == requestGeneration { loadTask = nil }
            throw error
        }
    }

    func invalidate() {
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        cached = nil
    }
}
