import Foundation

struct RemoteSessionCatalogSnapshot: Sendable, Equatable {
    let generation: RemoteConnectionGeneration
    let items: [RemoteSessionSummary]
    let errors: [String: String]
}

actor RemoteEventRuntime {
    private let channel: RemoteEventChannel
    private let sessions: any SessionControllerAPI
    private var catalog: RemoteSessionCatalogSnapshot?
    private var pendingSessionFrames: [RemoteEventDownlinkFrame] = []
    private var eventTask: Task<Void, Never>?
    private var catalogObservers: [UUID: AsyncStream<RemoteSessionCatalogSnapshot?>.Continuation] = [:]
    private var otherObservers: [UUID: AsyncStream<RemoteEventDownlinkFrame>.Continuation] = [:]
    private var interactionObservers: [UUID: AsyncStream<RemoteSessionInteractionUpdate>.Continuation] = [:]

    init(channel: RemoteEventChannel, sessions: any SessionControllerAPI) {
        self.channel = channel
        self.sessions = sessions
    }

    deinit { eventTask?.cancel() }

    func open() async throws -> RemoteSessionCatalogSnapshot {
        if let catalog { return catalog }
        if eventTask == nil { startConsuming() }
        let baseline = try await sessions.list()
        catalog = .init(generation: channel.generation, items: sort(baseline.items), errors: [:])
        let buffered = pendingSessionFrames
        pendingSessionFrames.removeAll(keepingCapacity: false)
        for frame in buffered { try applySessionFrame(frame) }
        let opened = catalog!
        publishCatalog(opened)
        return opened
    }

    func currentCatalog() -> RemoteSessionCatalogSnapshot? { catalog }

    func catalogs() -> AsyncStream<RemoteSessionCatalogSnapshot?> {
        let id = UUID()
        let pair = AsyncStream<RemoteSessionCatalogSnapshot?>.makeStream()
        catalogObservers[id] = pair.continuation
        pair.continuation.yield(catalog)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeCatalogObserver(id) }
        }
        return pair.stream
    }

    func otherEvents() -> AsyncStream<RemoteEventDownlinkFrame> {
        let id = UUID()
        let pair = AsyncStream<RemoteEventDownlinkFrame>.makeStream()
        otherObservers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeOtherObserver(id) }
        }
        return pair.stream
    }

    func interactions() -> AsyncStream<RemoteSessionInteractionUpdate> {
        let id = UUID()
        let pair = AsyncStream<RemoteSessionInteractionUpdate>.makeStream()
        interactionObservers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeInteractionObserver(id) }
        }
        return pair.stream
    }

    func reply(eventID: String, outcome: RemoteEventReplyOutcome) async throws {
        try await channel.reply(eventID: eventID, outcome: outcome)
    }

    func close() {
        eventTask?.cancel()
        eventTask = nil
        catalog = nil
        pendingSessionFrames.removeAll()
        publishCatalog(nil)
    }

    private func startConsuming() {
        eventTask = Task { [weak self, events = channel.events] in
            do {
                for try await frame in events {
                    guard let self else { return }
                    await self.receive(frame)
                }
                await self?.invalidateCatalog()
            } catch is CancellationError {
                return
            } catch {
                await self?.invalidateCatalog()
            }
        }
    }

    private func receive(_ frame: RemoteEventDownlinkFrame) {
        if isSessionCatalogFrame(frame) {
            guard catalog != nil else {
                pendingSessionFrames.append(frame)
                return
            }
            do {
                try applySessionFrame(frame)
                if let catalog { publishCatalog(catalog) }
            } catch {
                invalidateCatalog()
            }
            return
        }
        if let interaction = RemoteInteractionProjector.project(frame) {
            for observer in interactionObservers.values { observer.yield(interaction) }
        }
        for observer in otherObservers.values { observer.yield(frame) }
    }

    private func isSessionCatalogFrame(_ frame: RemoteEventDownlinkFrame) -> Bool {
        guard case let .emit(event, _) = frame else { return false }
        return event == "api-session/added"
            || event == "api-session/removed"
            || event == "api-session/status"
            || event == "api-session/activity"
            || event == "api-session/error"
    }

    private func applySessionFrame(_ frame: RemoteEventDownlinkFrame) throws {
        guard var current = catalog, case let .emit(event, args) = frame else { return }
        var byID = Dictionary(uniqueKeysWithValues: current.items.map { ($0.sessionId, $0) })
        var errors = current.errors
        switch event {
        case "api-session/added":
            guard args.count == 1 else { throw RemoteConnectionError.protocolViolation("api-session/added arguments") }
            let summary: RemoteSessionSummary = try decode(args[0], as: RemoteSessionSummary.self)
            byID[summary.sessionId] = summary
        case "api-session/removed":
            guard args.count == 1, case let .string(sessionID) = args[0] else { throw RemoteConnectionError.protocolViolation("api-session/removed arguments") }
            byID.removeValue(forKey: sessionID)
            errors.removeValue(forKey: sessionID)
        case "api-session/status":
            guard args.count == 2,
                  case let .string(sessionID) = args[0],
                  case let .bool(running) = args[1],
                  let item = byID[sessionID]
            else { throw RemoteConnectionError.protocolViolation("api-session/status arguments") }
            byID[sessionID] = replacing(item, running: running)
        case "api-session/activity":
            guard args.count == 2,
                  case let .string(sessionID) = args[0],
                  case let .number(updatedAt) = args[1],
                  let item = byID[sessionID]
            else { throw RemoteConnectionError.protocolViolation("api-session/activity arguments") }
            byID[sessionID] = replacing(item, updatedAt: Int64(updatedAt))
        case "api-session/error":
            guard args.count == 2,
                  case let .string(sessionID) = args[0],
                  case let .string(message) = args[1]
            else { throw RemoteConnectionError.protocolViolation("api-session/error arguments") }
            errors[sessionID] = message
        default:
            return
        }
        current = .init(generation: channel.generation, items: sort(Array(byID.values)), errors: errors)
        catalog = current
    }

    private func replacing(
        _ item: RemoteSessionSummary,
        running: Bool? = nil,
        updatedAt: Int64? = nil
    ) -> RemoteSessionSummary {
        .init(
            sessionId: item.sessionId,
            updatedAt: updatedAt ?? item.updatedAt,
            running: running ?? item.running,
            blank: item.blank,
            parentSessionId: item.parentSessionId,
            origin: item.origin,
            cwd: item.cwd,
            projections: item.projections
        )
    }

    private func sort(_ items: [RemoteSessionSummary]) -> [RemoteSessionSummary] {
        items.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.sessionId < right.sessionId
        }
    }

    private func decode<Value: Decodable>(_ value: RemoteJSONValue, as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }

    private func invalidateCatalog() {
        catalog = nil
        publishCatalog(nil)
    }

    private func publishCatalog(_ value: RemoteSessionCatalogSnapshot?) {
        for observer in catalogObservers.values { observer.yield(value) }
    }

    private func removeCatalogObserver(_ id: UUID) { catalogObservers.removeValue(forKey: id) }
    private func removeOtherObserver(_ id: UUID) { otherObservers.removeValue(forKey: id) }
    private func removeInteractionObserver(_ id: UUID) { interactionObservers.removeValue(forKey: id) }
}
