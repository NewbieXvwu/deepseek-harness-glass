import Foundation

struct WorkspaceRuntimeState: Sendable, Equatable {
    let generation: RemoteConnectionGeneration
    var items: [RemoteWorkspaceView]
    var archivedSessionIDs: [String]
}

enum WorkspaceRuntimeError: Error, Sendable, Equatable {
    case missingBaseline
    case duplicateBaseline
    case invalidOrder
}

actor WorkspaceRuntime {
    private let controller: WorkspaceControllerAPI
    private var activeGeneration: RemoteConnectionGeneration?
    private var state: WorkspaceRuntimeState?
    private var streamTask: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<WorkspaceRuntimeState>.Continuation] = [:]

    init(controller: WorkspaceControllerAPI) {
        self.controller = controller
    }

    func start(generation: RemoteConnectionGeneration) async throws {
        streamTask?.cancel()
        streamTask = nil
        activeGeneration = generation
        state = nil

        let stream = try await controller.follow()
        var iterator = stream.makeAsyncIterator()
        guard let opening = try await iterator.next(), case let .baseline(baseline) = opening else {
            activeGeneration = nil
            throw WorkspaceRuntimeError.missingBaseline
        }
        install(baseline, generation: generation)

        streamTask = Task { [weak self] in
            do {
                while let frame = try await iterator.next() {
                    guard let self else { return }
                    try await self.apply(frame, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                await self.invalidate(generation: generation)
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        activeGeneration = nil
        state = nil
    }

    func current() -> WorkspaceRuntimeState? { state }

    func rename(workspaceID: String, title: String) async throws -> RemoteWorkspaceValue {
        let value = try await controller.rename(workspaceID: workspaceID, title: title)
        if let generation = activeGeneration {
            try apply(.upsert(value.workspace), generation: generation)
        }
        return value
    }

    func delete(workspaceID: String) async throws -> RemoteWorkspaceDeleteValue {
        let value = try await controller.delete(workspaceID: workspaceID)
        if value.deleted, let generation = activeGeneration {
            try apply(.remove(workspaceID), generation: generation)
        }
        return value
    }

    func insertBefore(workspaceID: String, beforeWorkspaceID: String?) async throws -> RemoteWorkspaceOrderValue {
        let value = try await controller.insertBefore(workspaceID: workspaceID, beforeWorkspaceID: beforeWorkspaceID)
        if let generation = activeGeneration {
            try apply(.order(value.workspaceIds), generation: generation)
        }
        return value
    }

    func insertSessionBefore(
        workspaceID: String,
        sessionID: String,
        beforeSessionID: String?
    ) async throws -> RemoteWorkspaceValue {
        let value = try await controller.insertSessionBefore(
            workspaceID: workspaceID,
            sessionID: sessionID,
            beforeSessionID: beforeSessionID
        )
        if let generation = activeGeneration {
            try apply(.upsert(value.workspace), generation: generation)
        }
        return value
    }

    func archiveSession(sessionID: String) async throws -> RemoteWorkspaceArchiveValue {
        let value = try await controller.archiveSession(sessionID: sessionID)
        if let generation = activeGeneration {
            try apply(.archived(value.archivedSessionIds), generation: generation)
        }
        return value
    }

    func snapshots() -> AsyncStream<WorkspaceRuntimeState> {
        let id = UUID()
        let pair = AsyncStream<WorkspaceRuntimeState>.makeStream()
        observers[id] = pair.continuation
        if let state { pair.continuation.yield(state) }
        pair.continuation.onTermination = { @Sendable [weak self] _ in
            guard let self else { return }
            Task { await self.removeObserver(id) }
        }
        return pair.stream
    }

    private func install(_ baseline: RemoteWorkspaceBaseline, generation: RemoteConnectionGeneration) {
        state = .init(generation: generation, items: baseline.items, archivedSessionIDs: baseline.archivedSessionIds)
        publish()
    }

    private func apply(_ frame: RemoteWorkspaceFollowFrame, generation: RemoteConnectionGeneration) throws {
        guard activeGeneration == generation, var current = state else { return }
        switch frame {
        case .baseline:
            throw WorkspaceRuntimeError.duplicateBaseline
        case let .upsert(workspace):
            if let index = current.items.firstIndex(where: { $0.workspaceId == workspace.workspaceId }) {
                current.items[index] = workspace
            } else {
                current.items.append(workspace)
            }
        case let .remove(workspaceID):
            current.items.removeAll { $0.workspaceId == workspaceID }
        case let .order(workspaceIDs):
            let byID = Dictionary(uniqueKeysWithValues: current.items.map { ($0.workspaceId, $0) })
            guard workspaceIDs.count == current.items.count,
                  Set(workspaceIDs) == Set(byID.keys)
            else { throw WorkspaceRuntimeError.invalidOrder }
            current.items = workspaceIDs.compactMap { byID[$0] }
        case let .archived(sessionIDs):
            current.archivedSessionIDs = sessionIDs
        }
        state = current
        publish()
    }

    private func invalidate(generation: RemoteConnectionGeneration) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        state = nil
    }

    private func publish() {
        guard let state else { return }
        for observer in observers.values { observer.yield(state) }
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
