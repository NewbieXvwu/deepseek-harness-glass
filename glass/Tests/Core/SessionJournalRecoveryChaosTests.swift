import XCTest

@testable import GlassCore

final class SessionJournalRecoveryChaosTests: XCTestCase {
    private struct Generator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &+ 0x9e3779b97f4a7c15
        }

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        mutating func bounded(_ upperBound: Int) -> Int {
            precondition(upperBound > 0)
            return Int(next() % UInt64(upperBound))
        }
    }

    func testRandomReconnectGapAndReplayRecoveryConvergesToCanonicalFreshJournal() throws {
        for seed in 1...96 {
            var random = Generator(seed: UInt64(seed))
            let finalSeq = 24 + random.bounded(17)
            var generationValue: UInt64 = 1
            var generation = RemoteConnectionGeneration(rawValue: generationValue)
            let initialCut = 1 + random.bounded(6)
            var journal = SessionJournal()
            try journal.open(
                generation: generation,
                address: address,
                frame: opening(cursor: initialCut)
            )
            var applied = initialCut

            while applied < finalSeq {
                switch random.bounded(8) {
                case 0:
                    // A carrier generation may reopen at a later authoritative cut
                    // than the last frame the old client observed.
                    generationValue &+= 1
                    generation = .init(rawValue: generationValue)
                    let advanced = min(finalSeq, applied + random.bounded(3))
                    try journal.replaceOpening(
                        generation: generation,
                        address: address,
                        frame: opening(cursor: advanced)
                    )
                    applied = advanced

                case 1 where applied + 2 <= finalSeq:
                    // A skipped sequence is never guessed locally. The failed frame
                    // leaves state untouched, then a fresh opening supplies the cut.
                    let before = journal.snapshot
                    let observedGap = applied + 2
                    XCTAssertThrowsError(
                        try journal.append(generation: generation, event: event(observedGap)),
                        "seed \(seed)"
                    ) { error in
                        XCTAssertEqual(
                            error as? SessionJournalError,
                            .liveGap(
                                expected: SessionSeq(rawValue: applied + 1),
                                actual: SessionSeq(rawValue: observedGap)
                            ),
                            "seed \(seed)"
                        )
                    }
                    XCTAssertEqual(journal.snapshot, before, "seed \(seed)")
                    try journal.replaceOpening(
                        generation: generation,
                        address: address,
                        frame: opening(cursor: observedGap)
                    )
                    applied = observedGap

                case 2:
                    // Exact replay is idempotent.
                    let before = journal.snapshot
                    XCTAssertFalse(
                        try journal.append(generation: generation, event: event(applied)),
                        "seed \(seed)"
                    )
                    XCTAssertEqual(journal.snapshot, before, "seed \(seed)")

                case 3:
                    // Same durable sequence with different content is a repair signal,
                    // never an alternative locally accepted history.
                    let before = journal.snapshot
                    XCTAssertThrowsError(
                        try journal.append(
                            generation: generation,
                            event: event(applied, content: "conflict-\(seed)-\(applied)")
                        ),
                        "seed \(seed)"
                    ) { error in
                        XCTAssertEqual(
                            error as? SessionJournalError,
                            .duplicateConflict(seq: SessionSeq(rawValue: applied)),
                            "seed \(seed)"
                        )
                    }
                    XCTAssertEqual(journal.snapshot, before, "seed \(seed)")
                    try journal.replaceOpening(
                        generation: generation,
                        address: address,
                        frame: opening(cursor: applied)
                    )

                default:
                    applied += 1
                    XCTAssertTrue(
                        try journal.append(generation: generation, event: event(applied)),
                        "seed \(seed)"
                    )
                }
            }

            let recovered = try XCTUnwrap(journal.snapshot, "seed \(seed)")
            XCTAssertEqual(recovered.records, records(through: finalSeq), "seed \(seed)")
            XCTAssertEqual(recovered.appliedThrough, SessionSeq(rawValue: finalSeq), "seed \(seed)")

            // One more carrier generation must converge the durable journal authority
            // to the same state as a fresh client opening. `revision` deliberately
            // remains instance-local and records how many accepted mutations occurred.
            generationValue &+= 1
            generation = .init(rawValue: generationValue)
            try journal.replaceOpening(
                generation: generation,
                address: address,
                frame: opening(cursor: finalSeq)
            )
            var fresh = SessionJournal()
            try fresh.open(
                generation: generation,
                address: address,
                frame: opening(cursor: finalSeq)
            )
            let repaired = try XCTUnwrap(journal.snapshot, "seed \(seed)")
            let canonical = try XCTUnwrap(fresh.snapshot, "seed \(seed)")
            XCTAssertEqual(repaired.generation, canonical.generation, "seed \(seed)")
            XCTAssertEqual(repaired.address, canonical.address, "seed \(seed)")
            XCTAssertEqual(repaired.header, canonical.header, "seed \(seed)")
            XCTAssertEqual(repaired.openingCut, canonical.openingCut, "seed \(seed)")
            XCTAssertEqual(repaired.records, canonical.records, "seed \(seed)")
            XCTAssertEqual(repaired.hasMore, canonical.hasMore, "seed \(seed)")
            XCTAssertEqual(repaired.projections, canonical.projections, "seed \(seed)")
            XCTAssertEqual(repaired.appliedThrough, canonical.appliedThrough, "seed \(seed)")
            XCTAssertEqual(repaired.mutation, canonical.mutation, "seed \(seed)")
        }
    }

    private var address: SessionAddress {
        .session(sessionID: "chaos-session")
    }

    private func opening(cursor: Int) -> RemoteSessionFollowFrame {
        .snapshot(
            header: .init(
                version: 1,
                id: "chaos-session",
                createdAt: 1,
                cwd: "/tmp",
                parentSession: nil,
                seedLength: nil,
                origin: nil,
                delegationDepth: nil,
                agentPreset: nil
            ),
            cursor: SessionSeq(rawValue: cursor),
            records: records(through: cursor),
            hasMore: false,
            projections: .init(
                asOfSeq: SessionSeq(rawValue: cursor),
                values: ["cursor": .number(Double(cursor))]
            )
        )
    }

    private func records(through cursor: Int) -> [RemoteSessionHistoryRecord] {
        (1...cursor).map { .event(event($0)) }
    }

    private func event(_ seq: Int, content: String? = nil) -> RemoteSessionWireEvent {
        .init(
            type: "user/message",
            seq: SessionSeq(rawValue: seq),
            time: Int64(seq),
            data: .object(["content": .string(content ?? "event-\(seq)")]),
            ignorable: false,
            sourceEventSeqs: nil,
            surfaceOp: .string("append")
        )
    }
}
