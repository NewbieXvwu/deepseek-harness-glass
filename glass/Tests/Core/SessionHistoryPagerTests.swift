import XCTest

@testable import GlassCore

@MainActor
final class SessionHistoryPagerTests: XCTestCase {
    func testTailAndOlderPagePreserveOneContinuousRawRangeIncludingCompactionBoundary() async {
        let pager = SessionHistoryPager()
        var calls: [(String, Int?, Int?)] = []
        pager.bind(sessionID: "session") { sessionID, beforeSeq, maxMessages in
            calls.append((sessionID, beforeSeq, maxMessages))
            switch calls.count {
            case 1:
                return response([
                    event(10, "context/replacement"),
                    event(11, "assistant/message"),
                ], hasMore: true)
            case 2:
                return response([
                    event(7, "user/message"),
                    event(8, "compaction/summary"),
                    event(9, "context/injection"),
                ], hasMore: false)
            default:
                XCTFail("hasMore=false must stop repeat backward calls")
                return response([], hasMore: false)
            }
        }

        let loadedTail = await pager.loadTail()
        XCTAssertTrue(loadedTail)
        XCTAssertEqual(pager.rawRange, 10...11)
        let loadedOlder = await pager.loadOlder()
        XCTAssertTrue(loadedOlder)

        XCTAssertEqual(calls.map(\.1), [nil, 10])
        XCTAssertEqual(calls.map(\.2), [SessionHistoryPager.pageMessages, SessionHistoryPager.pageMessages])
        XCTAssertEqual(pager.entries.map(\.event.seq), [7, 8, 9, 10, 11])
        XCTAssertEqual(pager.entries.map(\.event.type), [
            "user/message", "compaction/summary", "context/injection", "context/replacement", "assistant/message",
        ])
        XCTAssertEqual(pager.rawRange, 7...11)
        XCTAssertFalse(pager.hasMore)
        let attemptedExtraPage = await pager.loadOlder()
        XCTAssertFalse(attemptedExtraPage)
        XCTAssertEqual(calls.count, 2)
    }

    func testDiscontinuousOrUnorderedOlderPageNeverMutatesExistingWindow() async {
        let pager = SessionHistoryPager()
        var requests = 0
        pager.bind(sessionID: "session") { _, beforeSeq, _ in
            requests += 1
            if beforeSeq == nil { return response([event(10, "assistant/message")], hasMore: true) }
            // The official client refuses an older page whose tail is not
            // immediately before the current base seq; this would create a gap.
            return response([event(7, "user/message"), event(8, "compaction/summary")], hasMore: true)
        }

        let loadedTail = await pager.loadTail()
        XCTAssertTrue(loadedTail)
        let loadedDiscontinuousPage = await pager.loadOlder()
        XCTAssertFalse(loadedDiscontinuousPage)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(pager.entries.map(\.event.seq), [10])
        XCTAssertFalse(pager.hasMore)
        guard case let .failed(_, beforeSeq, error) = pager.olderState else {
            return XCTFail("discontinuous page must leave a typed older-page failure")
        }
        XCTAssertEqual(beforeSeq, 10)
        guard case .decoding = error else { return XCTFail("expected integrity decoding error") }
    }

    func testDuplicateOrDescendingTailFailsThenRetryUsesSameBoundSource() async {
        let pager = SessionHistoryPager()
        var attempts = 0
        pager.bind(sessionID: "session") { _, _, _ in
            attempts += 1
            if attempts == 1 { return response([event(4, "user/message"), event(4, "assistant/message")], hasMore: false) }
            return response([event(4, "user/message"), event(5, "assistant/message")], hasMore: false)
        }

        let loadedDuplicateTail = await pager.loadTail()
        XCTAssertFalse(loadedDuplicateTail)
        guard case .failed = pager.tailState else { return XCTFail("duplicate tail page must fail") }
        let retriedTail = await pager.retryTail()
        XCTAssertTrue(retriedTail)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(pager.entries.map(\.event.seq), [4, 5])
        XCTAssertEqual(pager.tailState, .ready(sessionID: "session"))
    }

    func testLiveAcceptanceIsSequenceGuardedAfterTailLoad() async {
        let pager = SessionHistoryPager()
        pager.bind(sessionID: "session") { _, _, _ in response([entry(20, "assistant/message")], hasMore: false) }
        let loadedTail = await pager.loadTail()
        XCTAssertTrue(loadedTail)

        XCTAssertEqual(pager.acceptLive(entry(20, "assistant/message")), .duplicate)
        XCTAssertEqual(pager.acceptLive(entry(22, "assistant/message")), .gap(expected: 21, received: 22))
        XCTAssertEqual(pager.acceptLive(entry(21, "assistant/message")), .appended)
        XCTAssertEqual(pager.entries.map(\.event.seq), [20, 21])
    }

    private func response(_ events: [SessionHistoryEntryDTO], hasMore: Bool) -> SessionHistoryResponse {
        SessionHistoryResponse(events: events, hasMore: hasMore, projections: nil)
    }

    private func entry(_ seq: Int, _ type: String) -> SessionHistoryEntryDTO {
        SessionHistoryEntryDTO(event: event(seq, type), view: nil)
    }

    private func event(_ seq: Int, _ type: String) -> SessionEventDTO {
        SessionEventDTO(
            type: type,
            seq: seq,
            time: Double(seq),
            data: .object(["fixture": .string(type)]),
            sourceEventSeqs: nil,
            ignorable: nil
        )
    }
}
