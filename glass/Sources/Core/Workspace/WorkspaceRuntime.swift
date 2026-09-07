import Foundation

struct WorkspaceRuntimeState: Sendable, Equatable {
    let generation: RemoteConnectionGeneration
    var items: [RemoteWorkspaceView]
    var archivedSessionIDs: [String]
}

enum WorkspaceRuntimeError: Error, Sendable, Equatable {
    case missingBaseline
}

/// 纯函数领域状态机：无锁、无异步、零副作用、绝不抛出异常
enum WorkspaceStateReducer {
    static func reduce(
        current: WorkspaceRuntimeState,
        frame: RemoteWorkspaceFollowFrame
    ) -> WorkspaceRuntimeState {
        var next = current
        switch frame {
        case .baseline:
            // Opening snapshots are handled by WorkspaceRuntime before reducer entry.
            return current
        case let .upsert(workspace):
            if let index = next.items.firstIndex(where: { $0.workspaceId == workspace.workspaceId }) {
                next.items[index] = workspace
            } else {
                next.items.append(workspace)
            }
            return next
        case let .remove(workspaceID):
            next.items.removeAll { $0.workspaceId == workspaceID }
            return next
        case let .order(workspaceIDs):
            // 纯函数防御性排序对齐：排已知项、忽略未知项、保留本地项追加末尾
            let byID = Dictionary(next.items.map { ($0.workspaceId, $0) }, uniquingKeysWith: { _, new in new })
            var ordered: [RemoteWorkspaceView] = []
            var seenIDs = Set<String>()
            for id in workspaceIDs {
                if let item = byID[id], !seenIDs.contains(id) {
                    ordered.append(item)
                    seenIDs.insert(id)
                }
            }
            for item in next.items where !seenIDs.contains(item.workspaceId) {
                ordered.append(item)
            }
            next.items = ordered
            return next
        case let .archived(sessionIDs):
            next.archivedSessionIDs = sessionIDs
            return next
        }
    }
}

actor WorkspaceRuntime {
    private let controller: WorkspaceControllerAPI
    private var activeGeneration: RemoteConnectionGeneration?
    private var state: WorkspaceRuntimeState?
    private var streamTask: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<WorkspaceRuntimeState?>.Continuation] = [:]

    init(controller: WorkspaceControllerAPI) {
        self.controller = controller
    }

    func start(generation: RemoteConnectionGeneration) async throws {
        streamTask?.cancel()
        streamTask = nil
        activeGeneration = generation
        state = nil

        let stream = try await controller.follow()
        return try await withCheckedThrowingContinuation { continuation in
            streamTask = Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                await self.runStreamLoop(stream: stream, generation: generation, initialContinuation: continuation)
            }
        }
    }

    private func runStreamLoop(
        stream: AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>,
        generation: RemoteConnectionGeneration,
        initialContinuation: CheckedContinuation<Void, Error>
    ) async {
        var pendingContinuation: CheckedContinuation<Void, Error>? = initialContinuation
        func resumeOnce(with result: Result<Void, Error>) {
            if let cont = pendingContinuation {
                pendingContinuation = nil
                cont.resume(with: result)
            }
        }

        do {
            for try await frame in stream {
                if pendingContinuation != nil {
                    guard case let .baseline(baseline) = frame else {
                        activeGeneration = nil
                        resumeOnce(with: .failure(WorkspaceRuntimeError.missingBaseline))
                        return
                    }
                    install(baseline, generation: generation)
                    resumeOnce(with: .success(()))
                } else {
                    if case .baseline = frame {
                        invalidate(generation: generation)
                        return
                    }
                    apply(frame, generation: generation)
                }
            }
            if pendingContinuation != nil {
                activeGeneration = nil
                resumeOnce(with: .failure(WorkspaceRuntimeError.missingBaseline))
            } else {
                invalidate(generation: generation)
            }
        } catch is CancellationError {
            resumeOnce(with: .failure(CancellationError()))
            return
        } catch {
            if pendingContinuation != nil {
                activeGeneration = nil
                resumeOnce(with: .failure(error))
            } else {
                invalidate(generation: generation)
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        activeGeneration = nil
        state = nil
        publish(nil)
    }

    func current() -> WorkspaceRuntimeState? { state }

    func create(path: String) async throws -> RemoteWorkspaceCreateValue {
        try await controller.create(path: path)
    }

    func rename(workspaceID: String, title: String) async throws -> RemoteWorkspaceValue {
        try await controller.rename(workspaceID: workspaceID, title: title)
    }

    func delete(workspaceID: String) async throws -> RemoteWorkspaceDeleteValue {
        try await controller.delete(workspaceID: workspaceID)
    }

    func insertBefore(workspaceID: String, beforeWorkspaceID: String?) async throws -> RemoteWorkspaceOrderValue {
        try await controller.insertBefore(workspaceID: workspaceID, beforeWorkspaceID: beforeWorkspaceID)
    }

    func insertSessionBefore(
        workspaceID: String,
        sessionID: String,
        beforeSessionID: String?
    ) async throws -> RemoteWorkspaceValue {
        try await controller.insertSessionBefore(
            workspaceID: workspaceID,
            sessionID: sessionID,
            beforeSessionID: beforeSessionID
        )
    }

    func archiveSession(sessionID: String) async throws -> RemoteWorkspaceArchiveValue {
        try await controller.archiveSession(sessionID: sessionID)
    }

    func snapshots() -> AsyncStream<WorkspaceRuntimeState?> {
        let id = UUID()
        let pair = AsyncStream<WorkspaceRuntimeState?>.makeStream()
        observers[id] = pair.continuation
        pair.continuation.yield(state)
        pair.continuation.onTermination = { @Sendable [weak self] _ in
            guard let self else { return }
            Task { await self.removeObserver(id) }
        }
        return pair.stream
    }

    private func install(_ baseline: RemoteWorkspaceBaseline, generation: RemoteConnectionGeneration) {
        state = .init(generation: generation, items: baseline.items, archivedSessionIDs: baseline.archivedSessionIds)
        publish(state)
    }

    private func apply(_ frame: RemoteWorkspaceFollowFrame, generation: RemoteConnectionGeneration) {
        guard activeGeneration == generation, let current = state else { return }
        let next = WorkspaceStateReducer.reduce(current: current, frame: frame)
        if next != current {
            state = next
            publish(next)
        }
    }

    private func invalidate(generation: RemoteConnectionGeneration) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        state = nil
        publish(nil)
    }

    private func publish(_ snapshot: WorkspaceRuntimeState?) {
        for observer in observers.values { observer.yield(snapshot) }
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
