import Foundation

actor SessionRuntime {
    private let controller: any SessionControllerAPI
    private let generation: RemoteConnectionGeneration
    private let address: SessionAddress
    private let maxMessages: Int?
    private var journal = SessionJournal()
    private var followTask: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<SessionJournalSnapshot>.Continuation] = [:]

    init(
        controller: any SessionControllerAPI,
        generation: RemoteConnectionGeneration,
        address: SessionAddress,
        maxMessages: Int? = nil
    ) {
        self.controller = controller
        self.generation = generation
        self.address = address
        self.maxMessages = maxMessages
    }

    deinit { followTask?.cancel() }

    func open() async throws -> SessionJournalSnapshot {
        if let snapshot = journal.snapshot { return snapshot }
        let stream = try await controller.follow(.init(address: address, maxMessages: maxMessages))
        var iterator = stream.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw SessionJournalError.missingOpeningSnapshot
        }
        try journal.open(generation: generation, address: address, frame: first)
        let initial = journal.snapshot!
        publish(initial)
        followTask = Task { [weak self] in
            guard let self else { return }
            await self.consume(iterator: iterator)
        }
        return initial
    }

    func currentSnapshot() -> SessionJournalSnapshot? { journal.snapshot }

    func snapshots() -> AsyncStream<SessionJournalSnapshot> {
        let id = UUID()
        let pair = AsyncStream<SessionJournalSnapshot>.makeStream()
        observers[id] = pair.continuation
        if let snapshot = journal.snapshot { pair.continuation.yield(snapshot) }
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return pair.stream
    }

    func loadOlder(maxMessages: Int? = nil) async throws -> SessionJournalSnapshot? {
        guard let current = journal.snapshot, current.hasMore else { return journal.snapshot }
        let before = current.firstSeq.map { SessionLogOffset(rawValue: $0.rawValue) }
        let page = try await controller.page(.init(
            address: address,
            throughSeq: current.openingCut,
            beforeSeq: before,
            maxMessages: maxMessages ?? self.maxMessages
        ))
        _ = try journal.prepend(generation: generation, page: page)
        if let snapshot = journal.snapshot { publish(snapshot) }
        return journal.snapshot
    }

    func close() {
        followTask?.cancel()
        followTask = nil
    }

    private func consume(
        iterator initialIterator: AsyncThrowingStream<RemoteSessionFollowFrame, Error>.Iterator
    ) async {
        var iterator = initialIterator
        do {
            while let frame = try await iterator.next() {
                do {
                    try acceptFollow(frame)
                } catch SessionJournalError.liveGap, SessionJournalError.partiallyOverlappingEntry {
                    try await repairFollowing()
                    return
                }
            }
        } catch is CancellationError {
            return
        } catch {
            // A physical carrier failure invalidates this generation upstream.
        }
    }

    private func repairFollowing() async throws {
        let stream = try await controller.follow(.init(address: address, maxMessages: maxMessages))
        var iterator = stream.makeAsyncIterator()
        guard let opening = try await iterator.next() else {
            throw SessionJournalError.missingOpeningSnapshot
        }
        try journal.replaceOpening(generation: generation, address: address, frame: opening)
        if let snapshot = journal.snapshot { publish(snapshot) }
        followTask = Task { [weak self] in
            guard let self else { return }
            await self.consume(iterator: iterator)
        }
    }

    private func acceptFollow(_ frame: RemoteSessionFollowFrame) throws {
        switch frame {
        case .snapshot:
            throw SessionJournalError.duplicateOpeningSnapshot
        case let .event(event):
            let changed = try journal.append(generation: generation, event: event)
            if changed, let snapshot = journal.snapshot { publish(snapshot) }
        }
    }

    private func publish(_ snapshot: SessionJournalSnapshot) {
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

}
