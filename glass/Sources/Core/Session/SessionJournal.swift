import Foundation

enum SessionJournalError: Error, Sendable, Equatable {
    case missingOpeningSnapshot
    case duplicateOpeningSnapshot
    case staleGeneration
    case invalidOpeningCursor(expected: SessionSeq, actual: SessionSeq)
    case discontinuousPage(previous: SessionSeq, next: SessionSeq)
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
    }

    @discardableResult
    mutating func append(
        generation: RemoteConnectionGeneration,
        event: RemoteSessionWireEvent
    ) throws -> Bool {
        guard var current = snapshot else { throw SessionJournalError.missingOpeningSnapshot }
        guard current.generation == generation else { throw SessionJournalError.staleGeneration }

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
        return accepted.count
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
