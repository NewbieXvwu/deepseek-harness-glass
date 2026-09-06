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
        return try await withCheckedThrowingContinuation { continuation in
            task = Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                await self.consume(stream: stream, initialContinuation: continuation)
            }
        }
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
        stream: AsyncThrowingStream<RemoteSessionControlFrame, Error>,
        initialContinuation: CheckedContinuation<SessionControlSnapshot, Error>
    ) async {
        var pendingContinuation: CheckedContinuation<SessionControlSnapshot, Error>? = initialContinuation
        func resumeOnce(with result: Result<SessionControlSnapshot, Error>) {
            if let cont = pendingContinuation {
                pendingContinuation = nil
                cont.resume(with: result)
            }
        }

        do {
            for try await frame in stream {
                if pendingContinuation != nil {
                    guard case let .baseline(value) = frame else {
                        resumeOnce(with: .failure(SessionControlRuntimeError.missingOpeningBaseline))
                        return
                    }
                    let opening = SessionControlSnapshot(
                        generation: generation,
                        queues: value.queues,
                        jobs: value.jobs,
                        projections: value.projections
                    )
                    snapshot = opening
                    publish(opening)
                    resumeOnce(with: .success(opening))
                } else {
                    try apply(frame)
                }
            }
            resumeOnce(with: .failure(SessionControlRuntimeError.missingOpeningBaseline))
        } catch is CancellationError {
            resumeOnce(with: .failure(CancellationError()))
            return
        } catch {
            if pendingContinuation != nil {
                resumeOnce(with: .failure(error))
            } else {
                snapshot = nil
                publish(nil)
            }
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
