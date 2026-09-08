import Foundation

enum SessionJournalError: Error, Sendable, Equatable {
    case missingOpeningSnapshot
    case duplicateOpeningSnapshot
    case staleGeneration
    case invalidOpeningCursor(expected: SessionSeq, actual: SessionSeq)
    case discontinuousPage(previous: SessionSeq, next: SessionSeq)
    case duplicateConflict(seq: SessionSeq)
    case partiallyOverlappingEntry(first: SessionSeq, last: SessionSeq, appliedThrough: SessionSeq)
    case liveGap(expected: SessionSeq, actual: SessionSeq)
    case discontinuousPrepend(expectedTail: SessionSeq, actualTail: SessionSeq)
}

enum SessionJournalMutation: Sendable, Equatable {
    case authoritativeReplace
    case append(startRecordIndex: Int)
    case prepend(acceptedRecordCount: Int)
}

struct SessionJournalSnapshot: Sendable, Equatable {
    let generation: RemoteConnectionGeneration
    let address: SessionAddress
    let header: RemoteSessionWireHeader
    let openingCut: SessionSeq
    fileprivate(set) var records: [RemoteSessionHistoryRecord]
    fileprivate(set) var hasMore: Bool
    let projections: RemoteSessionProjectionBaseline
    fileprivate(set) var appliedThrough: SessionSeq
    /// Monotonic durable-authority revision owned by one SessionJournal instance.
    /// Hand-built fixtures retain zero so projection code fails closed to a full fold.
    fileprivate(set) var revision: UInt64
    /// Exact structural change that produced `revision` in the production Journal.
    fileprivate(set) var mutation: SessionJournalMutation

    init(
        generation: RemoteConnectionGeneration,
        address: SessionAddress,
        header: RemoteSessionWireHeader,
        openingCut: SessionSeq,
        records: [RemoteSessionHistoryRecord],
        hasMore: Bool,
        projections: RemoteSessionProjectionBaseline,
        appliedThrough: SessionSeq,
        revision: UInt64 = 0,
        mutation: SessionJournalMutation = .authoritativeReplace
    ) {
        self.generation = generation
        self.address = address
        self.header = header
        self.openingCut = openingCut
        self.records = records
        self.hasMore = hasMore
        self.projections = projections
        self.appliedThrough = appliedThrough
        self.revision = revision
        self.mutation = mutation
    }

    var firstSeq: SessionSeq? { records.first?.firstSeq }
}

struct SessionJournal: Sendable {
    private(set) var snapshot: SessionJournalSnapshot?
    /// Maximum number of recent raw events retained for deduplication and conflict checks.
    private static let maxRawEventsCapacity = 2000
    /// Exact raw durable events observed by this runtime. Packed chunk rows keep
    /// their compact representation and therefore do not fabricate identities
    /// for member events that were never individually received.
    private var rawEventsBySeq: [SessionSeq: RemoteSessionWireEvent] = [:]
    private var revision: UInt64 = 0

    mutating func open(
        generation: RemoteConnectionGeneration,
        address: SessionAddress,
        frame: RemoteSessionFollowFrame
    ) throws {
        guard snapshot == nil else { throw SessionJournalError.duplicateOpeningSnapshot }
        try replaceOpening(generation: generation, address: address, frame: frame)
    }

    mutating func replaceOpening(
        generation: RemoteConnectionGeneration,
        address: SessionAddress,
        frame: RemoteSessionFollowFrame
    ) throws {
        guard case let .snapshot(header, cursor, records, hasMore, projections) = frame else {
            throw SessionJournalError.missingOpeningSnapshot
        }
        try Self.validatePage(records)
        let tail = records.last?.lastSeq ?? SessionSeq(rawValue: -1)
        guard tail == cursor else {
            throw SessionJournalError.invalidOpeningCursor(expected: cursor, actual: tail)
        }
        revision += 1
        snapshot = SessionJournalSnapshot(
            generation: generation,
            address: address,
            header: header,
            openingCut: cursor,
            records: records,
            hasMore: hasMore,
            projections: projections,
            appliedThrough: cursor,
            revision: revision,
            mutation: .authoritativeReplace
        )
        rawEventsBySeq.removeAll(keepingCapacity: true)
        registerRawEvents(in: records)
    }

    @discardableResult
    mutating func append(
        generation: RemoteConnectionGeneration,
        event: RemoteSessionWireEvent
    ) throws -> Bool {
        guard snapshot != nil else { throw SessionJournalError.missingOpeningSnapshot }
        guard snapshot!.generation == generation else { throw SessionJournalError.staleGeneration }

        if let known = rawEventsBySeq[event.seq] {
            guard known == event else { throw SessionJournalError.duplicateConflict(seq: event.seq) }
            return false
        }

        let entry = RemoteSessionHistoryRecord.event(event)
        let first = entry.firstSeq
        let last = entry.lastSeq
        let appliedThrough = snapshot!.appliedThrough
        if last <= appliedThrough { return false }
        if first <= appliedThrough {
            throw SessionJournalError.partiallyOverlappingEntry(
                first: first,
                last: last,
                appliedThrough: appliedThrough
            )
        }
        let expected = SessionSeq(rawValue: appliedThrough.rawValue + 1)
        guard first == expected else {
            throw SessionJournalError.liveGap(expected: expected, actual: first)
        }

        let startRecordIndex = snapshot!.records.count
        revision += 1
        snapshot!.records.append(entry)
        snapshot!.appliedThrough = last
        snapshot!.revision = revision
        snapshot!.mutation = .append(startRecordIndex: startRecordIndex)
        rawEventsBySeq[event.seq] = event
        pruneRawEventsIfNeeded()
        return true
    }

    @discardableResult
    mutating func prepend(
        generation: RemoteConnectionGeneration,
        page: RemoteSessionPageValue
    ) throws -> Int {
        guard snapshot != nil else { throw SessionJournalError.missingOpeningSnapshot }
        guard snapshot!.generation == generation else { throw SessionJournalError.staleGeneration }
        try Self.validatePage(page.records)
        try validateRawEvents(in: page.records)

        let accepted: [RemoteSessionHistoryRecord]
        if let first = snapshot!.records.first?.firstSeq {
            accepted = page.records.filter { $0.firstSeq < first }
            if let tail = accepted.last {
                let expectedTail = SessionSeq(rawValue: first.rawValue - 1)
                guard tail.lastSeq == expectedTail else {
                    throw SessionJournalError.discontinuousPrepend(
                        expectedTail: expectedTail,
                        actualTail: tail.lastSeq
                    )
                }
            }
        } else {
            accepted = page.records
        }

        let changed = !accepted.isEmpty || snapshot!.hasMore != page.hasMore
        guard changed else { return 0 }

        revision += 1
        if !accepted.isEmpty {
            snapshot!.records.insert(contentsOf: accepted, at: 0)
        }
        snapshot!.hasMore = page.hasMore
        snapshot!.revision = revision
        snapshot!.mutation = .prepend(acceptedRecordCount: accepted.count)
        registerRawEvents(in: accepted)
        return accepted.count
    }

    private func validateRawEvents(in records: [RemoteSessionHistoryRecord]) throws {
        for record in records {
            guard case let .event(event) = record, let known = rawEventsBySeq[event.seq] else { continue }
            guard known == event else { throw SessionJournalError.duplicateConflict(seq: event.seq) }
        }
    }

    private mutating func registerRawEvents(in records: [RemoteSessionHistoryRecord]) {
        for record in records {
            guard case let .event(event) = record else { continue }
            rawEventsBySeq[event.seq] = event
        }
        pruneRawEventsIfNeeded()
    }

    private mutating func pruneRawEventsIfNeeded() {
        guard rawEventsBySeq.count > Self.maxRawEventsCapacity else { return }
        let excess = rawEventsBySeq.count - Self.maxRawEventsCapacity
        let sortedKeys = rawEventsBySeq.keys.sorted()
        for key in sortedKeys.prefix(excess) {
            rawEventsBySeq.removeValue(forKey: key)
        }
    }

    private static func validatePage(_ records: [RemoteSessionHistoryRecord]) throws {
        guard var previous = records.first else { return }
        for record in records.dropFirst() {
            let expected = SessionSeq(rawValue: previous.lastSeq.rawValue + 1)
            guard record.firstSeq == expected else {
                throw SessionJournalError.discontinuousPage(
                    previous: previous.lastSeq,
                    next: record.firstSeq
                )
            }
            previous = record
        }
    }
}
