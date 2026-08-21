/// Host-connection coalescer for the RC8 New Session action. The coordinator
/// retains only an in-flight task keyed by an already Host-projected workspace
/// id; it never manufactures workspace or session facts.
@MainActor
final class NativeWorkspaceConnectionCoordinator {
    private var tasks: [String: Task<String, Error>] = [:]
    private var generations: [String: UInt] = [:]

    func connect(
        workspaceID: String,
        operation: @escaping @MainActor () async throws -> String
    ) async throws -> String {
        if let existing = tasks[workspaceID] {
            return try await existing.value
        }
        generations[workspaceID, default: 0] &+= 1
        let generation = generations[workspaceID] ?? 0
        let task = Task<String, Error> { @MainActor in
            try await operation()
        }
        tasks[workspaceID] = task
        defer {
            guard generations[workspaceID] == generation else { return }
            tasks[workspaceID] = nil
        }
        return try await task.value
    }

    func cancelAll() {
        for workspaceID in tasks.keys {
            generations[workspaceID, default: 0] &+= 1
        }
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
