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
        return try await startFollowing(isRepair: false)
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

    func resync() async throws -> SessionJournalSnapshot {
        followTask?.cancel()
        followTask = nil
        return try await startFollowing(isRepair: true)
    }

    func close() {
        followTask?.cancel()
        followTask = nil
    }

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

        var retryDelayNanoseconds: UInt64 = 200_000_000 // 200ms
        let maxRetryDelayNanoseconds: UInt64 = 3_000_000_000 // 3s
        var consecutiveFailures = 0
        let maxConsecutiveFailures = 10

        while !Task.isCancelled {
            var receivedOpening = false
            do {
                for try await frame in currentStream {
                    // 只要接收到任意帧，证明流是通畅的，重置重试计数与退避延迟
                    consecutiveFailures = 0
                    retryDelayNanoseconds = 200_000_000

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
                        } catch SessionJournalError.liveGap, SessionJournalError.partiallyOverlappingEntry {
                            break
                        }
                    }
                }
                if !receivedOpening {
                    throw SessionJournalError.missingOpeningSnapshot
                }
                if Task.isCancelled { return }
                isRepair = true
                currentStream = try await controller.follow(.init(address: address, maxMessages: maxMessages))
            } catch is CancellationError {
                resumeOnce(with: .failure(CancellationError()))
                return
            } catch {
                if pendingContinuation != nil {
                    // 首帧握手阶段失败，立即返回错误给调用方
                    resumeOnce(with: .failure(error))
                    return
                }
                // 运行态网络中断：严禁消极退出自杀！执行自愈重连
                consecutiveFailures += 1
                if consecutiveFailures > maxConsecutiveFailures || Task.isCancelled {
                    return
                }
                try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
                retryDelayNanoseconds = min(retryDelayNanoseconds * 2, maxRetryDelayNanoseconds)
                if Task.isCancelled { return }
                do {
                    isRepair = true
                    currentStream = try await controller.follow(.init(address: address, maxMessages: maxMessages))
                } catch {
                    // 重连失败，循环继续并下一次退避
                    continue
                }
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

    private func publish(_ snapshot: SessionJournalSnapshot) {
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

}
