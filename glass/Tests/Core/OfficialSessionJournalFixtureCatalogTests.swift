import XCTest

@testable import GlassCore

final class OfficialSessionJournalFixtureCatalogTests: XCTestCase {
    private let generation = RemoteConnectionGeneration(rawValue: 11)

    func testReviewedCasesReplayThroughProductionJournal() throws {
        let fixture = try OfficialSessionJournalFixtureCatalog.load()
        for replay in fixture.cases {
            var journal = SessionJournal()
            try journal.open(generation: generation, address: replay.address, frame: replay.opening)
            for event in replay.liveEvents {
                XCTAssertTrue(try journal.append(generation: generation, event: event), replay.id)
            }
            for page in replay.olderPages {
                _ = try journal.prepend(generation: generation, page: page)
            }
            if let repairOpening = replay.repairOpening {
                try journal.replaceOpening(
                    generation: generation,
                    address: replay.address,
                    frame: repairOpening
                )
            }

            var replayDeduplicatedCount = 0
            for event in replay.replayEvents {
                if try !journal.append(generation: generation, event: event) {
                    replayDeduplicatedCount += 1
                }
            }

            let snapshot = try XCTUnwrap(journal.snapshot, replay.id)
            XCTAssertEqual(snapshot.address, replay.address, replay.id)
            XCTAssertEqual(snapshot.openingCut.rawValue, replay.expected.openingCut, replay.id)
            XCTAssertEqual(snapshot.appliedThrough.rawValue, replay.expected.appliedThrough, replay.id)
            XCTAssertEqual(snapshot.firstSeq?.rawValue, replay.expected.firstSeq, replay.id)
            XCTAssertEqual(snapshot.records.count, replay.expected.recordCount, replay.id)
            XCTAssertEqual(snapshot.hasMore, replay.expected.hasMore, replay.id)
            XCTAssertEqual(snapshot.projections.asOfSeq.rawValue, replay.expected.projectionAsOfSeq, replay.id)
            XCTAssertEqual(snapshot.projections.values.keys.sorted(), replay.expected.projectionKeys.sorted(), replay.id)
            XCTAssertEqual(replayDeduplicatedCount, replay.expected.replayDeduplicatedCount, replay.id)
        }
    }

    func testDirectSubagentFixturePreservesDurableLogicalAddress() throws {
        let fixture = try OfficialSessionJournalFixtureCatalog.load()
        let replay = try XCTUnwrap(fixture.cases.first { $0.id == "direct-subagent-journal" })
        guard case let .subagent(parentSessionID, childSessionID, mode) = replay.address else {
            return XCTFail("direct-subagent fixture must retain the rc.1 logical address")
        }
        XCTAssertEqual(parentSessionID, "fixture-parent")
        XCTAssertEqual(childSessionID, "fixture-child")
        XCTAssertEqual(mode, .continuable)

        guard case let .snapshot(header, cursor, records, _, projections) = replay.opening else {
            return XCTFail("direct-subagent fixture must start with a follow snapshot")
        }
        XCTAssertEqual(header.id, childSessionID)
        XCTAssertEqual(header.parentSession, parentSessionID)
        XCTAssertEqual(header.origin, "subagent")
        XCTAssertEqual(header.cwd, "<fixture-workspace>")
        XCTAssertEqual(cursor.rawValue, 1)
        XCTAssertEqual(records.map(\.firstSeq.rawValue), [0, 1])
        XCTAssertEqual(records.last?.event.type, "subagent/descriptor")
        XCTAssertEqual(projections.asOfSeq.rawValue, 1)
        XCTAssertEqual(projections.values.keys.sorted(), ["subagent", "subagentTiming"])

        var journal = SessionJournal()
        try journal.open(generation: generation, address: replay.address, frame: replay.opening)
        let snapshot = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(snapshot.address, .subagent(
            parentSessionID: "fixture-parent",
            childSessionID: "fixture-child",
            mode: .continuable
        ))
        XCTAssertNotEqual(snapshot.address, .session(sessionID: "fixture-child"))
    }

    func testReconnectFixtureRepairsThenDeduplicatesReplayedTail() throws {
        let fixture = try OfficialSessionJournalFixtureCatalog.load()
        let replay = try XCTUnwrap(fixture.cases.first { $0.id == "reconnect-replay-dedupe" })
        let repairOpening = try XCTUnwrap(replay.repairOpening)
        let replayed = try XCTUnwrap(replay.replayEvents.only)

        var journal = SessionJournal()
        try journal.open(generation: generation, address: replay.address, frame: replay.opening)
        for event in replay.liveEvents {
            XCTAssertTrue(try journal.append(generation: generation, event: event))
        }
        try journal.replaceOpening(generation: generation, address: replay.address, frame: repairOpening)
        let repaired = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(repaired.openingCut.rawValue, 3)
        XCTAssertEqual(repaired.appliedThrough.rawValue, 3)
        XCTAssertFalse(try journal.append(generation: generation, event: replayed))
        XCTAssertEqual(journal.snapshot, repaired)
    }

    func testPackedAndLongTailRecordsPreserveInclusiveSequenceBounds() throws {
        let fixture = try OfficialSessionJournalFixtureCatalog.load()
        let packed = try XCTUnwrap(fixture.cases.first { $0.id == "packed-opening-live-prepend" })
        guard case let .snapshot(_, _, packedRecords, _, _) = packed.opening else {
            return XCTFail("packed fixture must start with a snapshot")
        }
        let packedRun = try XCTUnwrap(packedRecords.first { if case .chunks = $0 { true } else { false } })
        XCTAssertEqual(packedRun.firstSeq.rawValue, 2)
        XCTAssertEqual(packedRun.lastSeq.rawValue, 3)

        let longTail = try XCTUnwrap(fixture.cases.first { $0.id == "unfinished-assistant-long-tail" })
        guard case let .snapshot(_, _, longRecords, _, _) = longTail.opening else {
            return XCTFail("long-tail fixture must start with a snapshot")
        }
        let tail = try XCTUnwrap(longRecords.only)
        XCTAssertEqual(tail.firstSeq.rawValue, 1)
        XCTAssertEqual(tail.lastSeq.rawValue, 256)
        XCTAssertEqual(tail.event.type, "chunkrow/text-chunks")
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
