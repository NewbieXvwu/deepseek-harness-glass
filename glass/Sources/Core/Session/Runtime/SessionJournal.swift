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

struct SessionJournalSnapshot: Sendable, Equatable {
    let generation: RemoteConnectionGeneration
    let address: SessionAddress
    let header: RemoteSessionWireHeader
    let openingCut: SessionSeq
    let records: [RemoteSessionHistoryRecord]
    let hasMore: Bool
    let projections: RemoteSessionProjectionBaseline
    let appliedThrough: SessionSeq

    var firstSeq: SessionSeq? { records.first?.firstSeq }
}

struct SessionJournal: Sendable {
    private(set) var snapshot: SessionJournalSnapshot?
    /// Exact raw durable events observed by this runtime. Packed chunk rows keep
    /// their compact representation and therefore do not fabricate identities
    /// for member events that were never individually received.
    private var rawEventsBySeq: [SessionSeq: RemoteSessionWireEvent] = [:]

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
        try validateRawEvents(in: records)
        let tail = records.last?.lastSeq ?? SessionSeq(rawValue: -1)
        guard tail == cursor else {
            throw SessionJournalError.invalidOpeningCursor(expected: cursor, actual: tail)
        }
        snapshot = SessionJournalSnapshot(
            generation: generation,
            address: address,
            header: header,
            openingCut: cursor,
            records: records,
            hasMore: hasMore,
            projections: projections,
            appliedThrough: cursor
        )
        registerRawEvents(in: records)
    }

    @discardableResult
    mutating func append(
        generation: RemoteConnectionGeneration,
        event: RemoteSessionWireEvent
    ) throws -> Bool {
        guard var current = snapshot else { throw SessionJournalError.missingOpeningSnapshot }
        guard current.generation == generation else { throw SessionJournalError.staleGeneration }

        if let known = rawEventsBySeq[event.seq] {
            guard known == event else { throw SessionJournalError.duplicateConflict(seq: event.seq) }
            return false
        }

        let entry = RemoteSessionHistoryRecord.event(event)
        let first = entry.firstSeq
        let last = entry.lastSeq
        if last <= current.appliedThrough { return false }
        if first <= current.appliedThrough {
            throw SessionJournalError.partiallyOverlappingEntry(
                first: first,
                last: last,
                appliedThrough: current.appliedThrough
            )
        }
        let expected = SessionSeq(rawValue: current.appliedThrough.rawValue + 1)
        guard first == expected else {
            throw SessionJournalError.liveGap(expected: expected, actual: first)
        }

        var records = current.records
        records.append(entry)
        current = SessionJournalSnapshot(
            generation: current.generation,
            address: current.address,
            header: current.header,
            openingCut: current.openingCut,
            records: records,
            hasMore: current.hasMore,
            projections: current.projections,
            appliedThrough: last
        )
        rawEventsBySeq[event.seq] = event
        snapshot = current
        return true
    }

    @discardableResult
    mutating func prepend(
        generation: RemoteConnectionGeneration,
        page: RemoteSessionPageValue
    ) throws -> Int {
        guard var current = snapshot else { throw SessionJournalError.missingOpeningSnapshot }
        guard current.generation == generation else { throw SessionJournalError.staleGeneration }
        try Self.validatePage(page.records)
        try validateRawEvents(in: page.records)

        let accepted: [RemoteSessionHistoryRecord]
        if let first = current.records.first?.firstSeq {
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

        current = SessionJournalSnapshot(
            generation: current.generation,
            address: current.address,
            header: current.header,
            openingCut: current.openingCut,
            records: accepted + current.records,
            hasMore: page.hasMore,
            projections: current.projections,
            appliedThrough: current.appliedThrough
        )
        snapshot = current
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
