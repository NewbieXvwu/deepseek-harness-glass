import Foundation

struct SessionAddressedControlState: Sendable, Equatable {
    let generation: RemoteConnectionGeneration
    let queue: [RemoteSessionQueuedItem]
    let jobs: [RemoteSessionJob]
    let projections: RemoteSessionProjectionBaseline?
}

/// Transport-free input state published by one addressed Session runtime.
/// Durable journal authority and Host-wide transient control authority remain
/// distinct so projection code can reason about their independent lifetimes.
struct SessionRuntimeState: Sendable, Equatable {
    let journal: SessionJournalSnapshot
    let control: SessionAddressedControlState?
}

actor SessionRuntime {
    private let controller: any SessionControllerAPI
    private let generation: RemoteConnectionGeneration
    private let address: SessionAddress
    private let maxMessages: Int?
    private let controlRuntime: SessionControlRuntime?
    private let commands: SessionCommandService
    private var journal = SessionJournal()
    private var followTask: Task<Void, Never>?
    private var controlObservationTask: Task<Void, Never>?
    private var controlSnapshot: SessionControlSnapshot?
    private var observers: [UUID: AsyncStream<SessionJournalSnapshot>.Continuation] = [:]
    private var stateObservers: [UUID: AsyncStream<SessionRuntimeState>.Continuation] = [:]

    init(
        controller: any SessionControllerAPI,
        generation: RemoteConnectionGeneration,
        address: SessionAddress,
        maxMessages: Int? = nil,
        controlRuntime: SessionControlRuntime? = nil,
        interactions: (any SessionInteractionResponder)? = nil
    ) {
        self.controller = controller
        self.generation = generation
        self.address = address
        self.maxMessages = maxMessages
        self.controlRuntime = controlRuntime
        self.commands = SessionCommandService(controller: controller, interactions: interactions)
    }

    deinit {
        followTask?.cancel()
        controlObservationTask?.cancel()
    }

    func open() async throws -> SessionJournalSnapshot {
        startControlObservationIfNeeded()
        if let snapshot = journal.snapshot {
            publishStateIfAvailable()
            return snapshot
        }
        return try await startFollowing(isRepair: false)
    }

    func currentSnapshot() -> SessionJournalSnapshot? { journal.snapshot }

    func currentState() -> SessionRuntimeState? { composeState() }

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

    func states() -> AsyncStream<SessionRuntimeState> {
        let id = UUID()
        let pair = AsyncStream<SessionRuntimeState>.makeStream()
        stateObservers[id] = pair.continuation
        if let state = composeState() { pair.continuation.yield(state) }
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStateObserver(id) }
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

    func resync() async throws -> SessionJournalSnapshot {
        followTask?.cancel()
        followTask = nil
        startControlObservationIfNeeded()
        return try await startFollowing(isRepair: true)
    }

    func close() {
        followTask?.cancel()
        followTask = nil
        controlObservationTask?.cancel()
        controlObservationTask = nil
        controlSnapshot = nil
        publishStateIfAvailable()
    }

    // MARK: - Commands

    func makePromptIntent(
        mode: RemoteSessionPromptMode,
        content: [RemotePromptContentPart],
        clientTimeZone: String? = nil
    ) -> SessionPromptIntent {
        commands.makePromptIntent(
            sessionID: address.sessionID,
            mode: mode,
            content: content,
            clientTimeZone: clientTimeZone
        )
    }

    func submitPrompt(_ intent: SessionPromptIntent) async throws {
        try await commands.submitPrompt(intent)
    }

    func retryPrompt(_ intent: SessionPromptIntent) async throws {
        try await commands.retryPrompt(intent)
    }

    func cancel() async throws {
        try await commands.cancel(sessionID: address.sessionID)
    }

    func updateQueue(itemID: String, action: RemoteQueueAction) async throws {
        try await commands.updateQueue(sessionID: address.sessionID, itemID: itemID, action: action)
    }

    func answerApproval(eventID: String, allowOnce: Bool) async throws {
        try await commands.answerApproval(eventID: eventID, allowOnce: allowOnce)
    }

    func answerQuestion(eventID: String, answers: [SessionQuestionCommandAnswer]) async throws {
        try await commands.answerQuestion(eventID: eventID, answers: answers)
    }

    func cancelQuestion(eventID: String) async throws {
        try await commands.cancelQuestion(eventID: eventID)
    }

    func selectModel(_ selection: RemoteModelSelection) async throws -> RemoteModelSelection {
        try await commands.selectModel(sessionID: address.sessionID, selection: selection)
    }

    // MARK: - Journal follow

    private func startFollowing(isRepair: Bool) async throws -> SessionJournalSnapshot {
        let stream = try await controller.follow(.init(address: address, maxMessages: maxMessages))
        return try await withCheckedThrowingContinuation { continuation in
            followTask = Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                await self.runFollowLoop(initialStream: stream, initialRepair: isRepair, initialContinuation: continuation)
            }
        }
    }

    private func runFollowLoop(
        initialStream: AsyncThrowingStream<RemoteSessionFollowFrame, Error>,
        initialRepair: Bool,
        initialContinuation: CheckedContinuation<SessionJournalSnapshot, Error>
    ) async {
        var currentStream = initialStream
        var isRepair = initialRepair
        var pendingContinuation: CheckedContinuation<SessionJournalSnapshot, Error>? = initialContinuation

        func resumeOnce(with result: Result<SessionJournalSnapshot, Error>) {
            if let cont = pendingContinuation {
                pendingContinuation = nil
                cont.resume(with: result)
            }
        }

        while !Task.isCancelled {
            var receivedOpening = false
            var needsContinuityRepair = false
            do {
                for try await frame in currentStream {
                    if !receivedOpening {
                        receivedOpening = true
                        if isRepair {
                            try journal.replaceOpening(generation: generation, address: address, frame: frame)
                        } else {
                            try journal.open(generation: generation, address: address, frame: frame)
                        }
                        guard let snapshot = journal.snapshot else {
                            throw SessionJournalError.missingOpeningSnapshot
                        }
                        publish(snapshot)
                        resumeOnce(with: .success(snapshot))
                    } else {
                        do {
                            try acceptFollow(frame)
                        } catch SessionJournalError.liveGap,
                                SessionJournalError.partiallyOverlappingEntry,
                                SessionJournalError.duplicateConflict {
                            needsContinuityRepair = true
                            break
                        }
                    }
                }
                guard receivedOpening else {
                    throw SessionJournalError.missingOpeningSnapshot
                }
                guard !Task.isCancelled, needsContinuityRepair else { return }

                // Sequence continuity is a domain concern: replace the current
                // cut from a fresh opening snapshot. Carrier/business/protocol
                // failures never reach this path and are not replayed here.
                isRepair = true
                currentStream = try await controller.follow(.init(address: address, maxMessages: maxMessages))
            } catch is CancellationError {
                resumeOnce(with: .failure(CancellationError()))
                return
            } catch {
                if pendingContinuation != nil {
                    resumeOnce(with: .failure(error))
                }
                return
            }
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

    // MARK: - Control composition

    private func startControlObservationIfNeeded() {
        guard let controlRuntime, controlObservationTask == nil else { return }
        controlObservationTask = Task.detached { [weak self, controlRuntime] in
            let stream = await controlRuntime.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled else { return }
                await self?.acceptControlSnapshot(snapshot)
            }
        }
    }

    private func acceptControlSnapshot(_ snapshot: SessionControlSnapshot?) {
        if let snapshot, snapshot.generation == generation {
            controlSnapshot = snapshot
        } else {
            controlSnapshot = nil
        }
        publishStateIfAvailable()
    }

    private func composeState() -> SessionRuntimeState? {
        guard let journalSnapshot = journal.snapshot else { return nil }
        let control: SessionAddressedControlState?
        if let controlSnapshot, controlSnapshot.generation == generation {
            let sessionID = address.sessionID
            control = .init(
                generation: controlSnapshot.generation,
                queue: controlSnapshot.queues[sessionID] ?? [],
                jobs: controlSnapshot.jobs[sessionID] ?? [],
                projections: controlSnapshot.projections[sessionID]
            )
        } else {
            control = nil
        }
        return .init(journal: journalSnapshot, control: control)
    }

    private func publish(_ snapshot: SessionJournalSnapshot) {
        for continuation in observers.values { continuation.yield(snapshot) }
        publishStateIfAvailable()
    }

    private func publishStateIfAvailable() {
        guard let state = composeState() else { return }
        for continuation in stateObservers.values { continuation.yield(state) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func removeStateObserver(_ id: UUID) {
        stateObservers.removeValue(forKey: id)
    }
}
