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
                return self.response([
                    self.entry(10, "context/replacement"),
                    self.entry(11, "assistant/message"),
                ], hasMore: true)
            case 2:
                return self.response([
                    self.entry(7, "user/message"),
                    self.entry(8, "compaction/summary"),
                    self.entry(9, "context/injection"),
                ], hasMore: false)
            default:
                XCTFail("hasMore=false must stop repeat backward calls")
                return self.response([], hasMore: false)
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
            if beforeSeq == nil { return self.response([self.entry(10, "assistant/message")], hasMore: true) }
            // The official client refuses an older page whose tail is not
            // immediately before the current base seq; this would create a gap.
            return self.response([self.entry(7, "user/message"), self.entry(8, "compaction/summary")], hasMore: true)
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
            if attempts == 1 { return self.response([self.entry(4, "user/message"), self.entry(4, "assistant/message")], hasMore: false) }
            return self.response([self.entry(4, "user/message"), self.entry(5, "assistant/message")], hasMore: false)
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

    func testOlderPageLoadCoalescesWhileARequestIsInFlight() async {
        let pager = SessionHistoryPager()
        let gate = AsyncGate()
        var beforeSeqRequests: [Int?] = []
        var maxMessageRequests: [Int?] = []
        pager.bind(sessionID: "session") { _, beforeSeq, maxMessages in
            beforeSeqRequests.append(beforeSeq)
            maxMessageRequests.append(maxMessages)
            if beforeSeq == nil {
                return self.response([self.entry(10, "assistant/message")], hasMore: true)
            }
            await gate.wait()
            return self.response([self.entry(9, "user/message")], hasMore: false)
        }

        XCTAssertTrue(await pager.loadTail())
        let firstLoad = Task { await pager.loadOlder() }
        await self.waitUntil { pager.isLoadingOlder }

        let secondLoad = await pager.loadOlder()
        XCTAssertFalse(secondLoad)
        XCTAssertEqual(beforeSeqRequests, [nil, 10])
        XCTAssertEqual(maxMessageRequests, [SessionHistoryPager.pageMessages, SessionHistoryPager.pageMessages])

        await gate.open()
        XCTAssertTrue(await firstLoad.value)
        XCTAssertEqual(pager.entries.map(\.event.seq), [9, 10])
        XCTAssertFalse(pager.hasMore)
    }

    func testLiveAcceptanceIsSequenceGuardedAfterTailLoad() async {
        let pager = SessionHistoryPager()
        pager.bind(sessionID: "session") { _, _, _ in self.response([self.entry(20, "assistant/message")], hasMore: false) }
        let loadedTail = await pager.loadTail()
        XCTAssertTrue(loadedTail)

        XCTAssertEqual(pager.acceptLive(entry(20, "assistant/message")), .duplicate)
        XCTAssertEqual(pager.acceptLive(entry(22, "assistant/message")), .gap(expected: 21, received: 22))
        XCTAssertEqual(pager.acceptLive(entry(21, "assistant/message")), .appended)
        XCTAssertEqual(pager.entries.map(\.event.seq), [20, 21])
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        timeout: TimeInterval = 1
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(predicate(), "timed out waiting for the expected state")
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

private actor AsyncGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation in
            if opened {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
