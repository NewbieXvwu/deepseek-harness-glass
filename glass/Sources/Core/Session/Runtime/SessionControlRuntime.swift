import Foundation

struct SessionControlSnapshot: Sendable, Equatable {
    let generation: RemoteConnectionGeneration
    let queues: [String: [RemoteSessionQueuedItem]]
    let jobs: [String: [RemoteSessionJob]]
    let projections: [String: RemoteSessionProjectionBaseline]
}

enum SessionControlRuntimeError: Error, Sendable, Equatable {
    case missingOpeningBaseline
    case duplicateOpeningBaseline
}

actor SessionControlRuntime {
    private let controller: any SessionControllerAPI
    private let generation: RemoteConnectionGeneration
    private var snapshot: SessionControlSnapshot?
    private var task: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<SessionControlSnapshot?>.Continuation] = [:]

    init(controller: any SessionControllerAPI, generation: RemoteConnectionGeneration) {
        self.controller = controller
        self.generation = generation
    }

    deinit { task?.cancel() }

    func open() async throws -> SessionControlSnapshot {
        if let snapshot { return snapshot }
        let stream = try await controller.control()
        var iterator = stream.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw SessionControlRuntimeError.missingOpeningBaseline
        }
        guard case let .baseline(value) = first else {
            throw SessionControlRuntimeError.missingOpeningBaseline
        }
        let opening = SessionControlSnapshot(
            generation: generation,
            queues: value.queues,
            jobs: value.jobs,
            projections: value.projections
        )
        snapshot = opening
        publish(opening)
        task = Task { [weak self] in
            guard let self else { return }
            await self.consume(iterator: iterator)
        }
        return opening
    }

    func currentSnapshot() -> SessionControlSnapshot? { snapshot }

    func snapshots() -> AsyncStream<SessionControlSnapshot?> {
        let id = UUID()
        let pair = AsyncStream<SessionControlSnapshot?>.makeStream()
        observers[id] = pair.continuation
        pair.continuation.yield(snapshot)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return pair.stream
    }

    func invalidate() {
        task?.cancel()
        task = nil
        snapshot = nil
        publish(nil)
    }

    private func consume(
        iterator initialIterator: AsyncThrowingStream<RemoteSessionControlFrame, Error>.Iterator
    ) async {
        var iterator = initialIterator
        do {
            while let frame = try await iterator.next() {
                try apply(frame)
            }
        } catch is CancellationError {
            return
        } catch {
            snapshot = nil
            publish(nil)
        }
    }

    private func apply(_ frame: RemoteSessionControlFrame) throws {
        guard let current = snapshot else { return }
        switch frame {
        case .baseline:
            throw SessionControlRuntimeError.duplicateOpeningBaseline
        case let .queue(sessionID, items):
            var queues = current.queues
            queues[sessionID] = items
            snapshot = .init(
                generation: generation,
                queues: queues,
                jobs: current.jobs,
                projections: current.projections
            )
            publish(snapshot)
        case let .jobs(sessionID, jobs):
            var allJobs = current.jobs
            allJobs[sessionID] = jobs
            snapshot = .init(
                generation: generation,
                queues: current.queues,
                jobs: allJobs,
                projections: current.projections
            )
            publish(snapshot)
        case let .projection(sessionID, key, value, seq):
            var projections = current.projections
            let existing = projections[sessionID]
            var values = existing?.values ?? [:]
            values[key] = value
            projections[sessionID] = .init(asOfSeq: seq, values: values)
            snapshot = .init(
                generation: generation,
                queues: current.queues,
                jobs: current.jobs,
                projections: projections
            )
            publish(snapshot)
        }
    }

    private func publish(_ snapshot: SessionControlSnapshot?) {
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

}
