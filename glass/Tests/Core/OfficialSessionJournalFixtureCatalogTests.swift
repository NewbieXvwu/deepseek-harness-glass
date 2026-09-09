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

            let snapshot = try XCTUnwrap(journal.snapshot, replay.id)
            XCTAssertEqual(snapshot.address, replay.address, replay.id)
            XCTAssertEqual(snapshot.openingCut.rawValue, replay.expected.openingCut, replay.id)
            XCTAssertEqual(snapshot.appliedThrough.rawValue, replay.expected.appliedThrough, replay.id)
            XCTAssertEqual(snapshot.firstSeq?.rawValue, replay.expected.firstSeq, replay.id)
            XCTAssertEqual(snapshot.records.count, replay.expected.recordCount, replay.id)
            XCTAssertEqual(snapshot.hasMore, replay.expected.hasMore, replay.id)
        }
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
