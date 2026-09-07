import XCTest

@testable import GlassCore

final class SessionJournalTests: XCTestCase {
    private let generation = RemoteConnectionGeneration(rawValue: 7)
    private let address = SessionAddress.session(sessionID: "journal-test")

    func testOpeningSnapshotInstallsAuthoritativeCut() throws {
        var journal = SessionJournal()
        try journal.open(
            generation: generation,
            address: address,
            frame: opening(cursor: 2, records: [record(1), record(2)], hasMore: true)
        )

        let snapshot = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(snapshot.generation, generation)
        XCTAssertEqual(snapshot.address, address)
        XCTAssertEqual(snapshot.openingCut, SessionSeq(rawValue: 2))
        XCTAssertEqual(snapshot.appliedThrough, SessionSeq(rawValue: 2))
        XCTAssertEqual(snapshot.records.map(\.firstSeq), [SessionSeq(rawValue: 1), SessionSeq(rawValue: 2)])
        XCTAssertTrue(snapshot.hasMore)
    }

    func testOpeningSnapshotRejectsCursorThatDoesNotMatchPageTail() {
        var journal = SessionJournal()
        XCTAssertThrowsError(try journal.open(
            generation: generation,
            address: address,
            frame: opening(cursor: 3, records: [record(1), record(2)])
        )) { error in
            XCTAssertEqual(
                error as? SessionJournalError,
                .invalidOpeningCursor(expected: SessionSeq(rawValue: 3), actual: SessionSeq(rawValue: 2))
            )
        }
    }

    func testContiguousLiveAppendAdvancesAppliedThroughButKeepsOpeningCutFrozen() throws {
        var journal = try openedJournal(cursor: 2, records: [record(1), record(2)])

        XCTAssertTrue(try journal.append(generation: generation, event: event(3, text: "live")))

        let snapshot = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(snapshot.openingCut, SessionSeq(rawValue: 2))
        XCTAssertEqual(snapshot.appliedThrough, SessionSeq(rawValue: 3))
        XCTAssertEqual(snapshot.records.map(\.firstSeq), [
            SessionSeq(rawValue: 1), SessionSeq(rawValue: 2), SessionSeq(rawValue: 3),
        ])
    }

    func testReplayAtOrBehindAppliedCursorDoesNotMutateJournal() throws {
        var journal = try openedJournal(cursor: 2, records: [record(1), record(2)])
        let before = journal.snapshot

        XCTAssertFalse(try journal.append(generation: generation, event: event(2, text: "replayed")))
        XCTAssertEqual(journal.snapshot, before)
    }

    func testLiveAppendRejectsStaleGeneration() throws {
        var journal = try openedJournal(cursor: 1, records: [record(1)])

        XCTAssertThrowsError(try journal.append(
            generation: RemoteConnectionGeneration(rawValue: 6),
            event: event(2)
        )) { error in
            XCTAssertEqual(error as? SessionJournalError, .staleGeneration)
        }
        XCTAssertEqual(journal.snapshot?.appliedThrough, SessionSeq(rawValue: 1))
    }

    func testLiveAppendRejectsSequenceGapWithoutMutatingJournal() throws {
        var journal = try openedJournal(cursor: 1, records: [record(1)])
        let before = journal.snapshot

        XCTAssertThrowsError(try journal.append(generation: generation, event: event(3))) { error in
            XCTAssertEqual(
                error as? SessionJournalError,
                .liveGap(expected: SessionSeq(rawValue: 2), actual: SessionSeq(rawValue: 3))
            )
        }
        XCTAssertEqual(journal.snapshot, before)
    }

    func testContiguousOlderPagePrependsWithoutChangingOpeningOrLiveTail() throws {
        var journal = try openedJournal(cursor: 4, records: [record(3), record(4)], hasMore: true)
        XCTAssertTrue(try journal.append(generation: generation, event: event(5)))

        let accepted = try journal.prepend(
            generation: generation,
            page: .init(records: [record(1), record(2)], hasMore: false)
        )

        XCTAssertEqual(accepted, 2)
        let snapshot = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(snapshot.records.map(\.firstSeq), (1...5).map { SessionSeq(rawValue: $0) })
        XCTAssertEqual(snapshot.openingCut, SessionSeq(rawValue: 4))
        XCTAssertEqual(snapshot.appliedThrough, SessionSeq(rawValue: 5))
        XCTAssertFalse(snapshot.hasMore)
    }

    func testOlderPageOverlapIsTrimmedAtCurrentWindowBoundary() throws {
        var journal = try openedJournal(cursor: 4, records: [record(3), record(4)], hasMore: true)

        let accepted = try journal.prepend(
            generation: generation,
            page: .init(records: [record(1), record(2), record(3)], hasMore: false)
        )

        XCTAssertEqual(accepted, 2)
        XCTAssertEqual(journal.snapshot?.records.map(\.firstSeq), (1...4).map { SessionSeq(rawValue: $0) })
    }

    func testOlderPageRejectsDiscontinuousBoundaryAndRetainsCurrentWindow() throws {
        var journal = try openedJournal(cursor: 4, records: [record(3), record(4)], hasMore: true)
        let before = journal.snapshot

        XCTAssertThrowsError(try journal.prepend(
            generation: generation,
            page: .init(records: [record(1)], hasMore: false)
        )) { error in
            XCTAssertEqual(
                error as? SessionJournalError,
                .discontinuousPrepend(expectedTail: SessionSeq(rawValue: 2), actualTail: SessionSeq(rawValue: 1))
            )
        }
        XCTAssertEqual(journal.snapshot, before)
    }

    func testOlderPageRejectsInternalSequenceGap() throws {
        var journal = try openedJournal(cursor: 4, records: [record(3), record(4)], hasMore: true)

        XCTAssertThrowsError(try journal.prepend(
            generation: generation,
            page: .init(records: [record(0), record(2)], hasMore: false)
        )) { error in
            XCTAssertEqual(
                error as? SessionJournalError,
                .discontinuousPage(previous: SessionSeq(rawValue: 0), next: SessionSeq(rawValue: 2))
            )
        }
    }

    func testOlderPageRejectsStaleGeneration() throws {
        var journal = try openedJournal(cursor: 2, records: [record(1), record(2)], hasMore: true)
        let before = journal.snapshot

        XCTAssertThrowsError(try journal.prepend(
            generation: RemoteConnectionGeneration(rawValue: 8),
            page: .init(records: [], hasMore: false)
        )) { error in
            XCTAssertEqual(error as? SessionJournalError, .staleGeneration)
        }
        XCTAssertEqual(journal.snapshot, before)
    }

    private func openedJournal(
        cursor: Int,
        records: [RemoteSessionHistoryRecord],
        hasMore: Bool = false
    ) throws -> SessionJournal {
        var journal = SessionJournal()
        try journal.open(
            generation: generation,
            address: address,
            frame: opening(cursor: cursor, records: records, hasMore: hasMore)
        )
        return journal
    }

    private func opening(
        cursor: Int,
        records: [RemoteSessionHistoryRecord],
        hasMore: Bool = false
    ) -> RemoteSessionFollowFrame {
        .snapshot(
            header: .init(
                version: 1,
                id: "journal-test",
                createdAt: 1,
                cwd: "/tmp",
                parentSession: nil,
                seedLength: nil,
                origin: nil,
                delegationDepth: nil,
                agentPreset: nil
            ),
            cursor: SessionSeq(rawValue: cursor),
            records: records,
            hasMore: hasMore,
            projections: .init(asOfSeq: SessionSeq(rawValue: cursor), values: [:])
        )
    }

    private func record(_ seq: Int) -> RemoteSessionHistoryRecord {
        .event(event(seq))
    }

    private func event(_ seq: Int, text: String? = nil) -> RemoteSessionWireEvent {
        .init(
            type: "user/message",
            seq: SessionSeq(rawValue: seq),
            time: Int64(seq),
            data: .object(["content": .string(text ?? "event-\(seq)")]),
            ignorable: false,
            sourceEventSeqs: nil,
            surfaceOp: .string("append")
        )
    }
}
