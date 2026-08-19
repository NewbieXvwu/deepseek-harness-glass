import XCTest

@testable import GlassCore

@MainActor
final class SessionProjectionStoreTests: XCTestCase {
    func testHigherSequenceWinsWithinOneSessionAndSessionsRemainIsolated() {
        let store = SessionProjectionStore()
        store.apply(sessionID: "a", key: "title", value: .string("new"), seq: 20)
        store.apply(sessionID: "a", key: "title", value: .string("stale"), seq: 19)
        store.apply(sessionID: "a", key: "title", value: .string("replay"), seq: 20)
        store.apply(sessionID: "b", key: "title", value: .string("other"), seq: 1)

        XCTAssertEqual(store.value(sessionID: "a", key: "title"), .string("new"))
        XCTAssertEqual(store.row(sessionID: "a", key: "title")?.seq, 20)
        XCTAssertEqual(store.value(sessionID: "b", key: "title"), .string("other"))
    }

    func testHistoryBaselineSeedsAndClearsOnlyRowsNoNewerThanCut() {
        let store = SessionProjectionStore()
        store.apply(sessionID: "session", key: "title", value: .string("live"), seq: 30)
        store.apply(sessionID: "session", key: "todo", value: .string("old"), seq: 10)

        store.seed(sessionID: "session", baseline: SessionProjectionsDTO(
            asOfSeq: 20,
            values: ["title": .string("baseline")]
        ))

        XCTAssertEqual(store.value(sessionID: "session", key: "title"), .string("live"))
        XCTAssertNil(store.value(sessionID: "session", key: "todo"))
    }

    func testReconnectTruncationDropsOnlyValuesPastDurableWatermark() {
        let store = SessionProjectionStore()
        store.apply(sessionID: "session", key: "title", value: .string("durable"), seq: 12)
        store.apply(sessionID: "session", key: "todo", value: .string("transient"), seq: 15)

        store.truncate(sessionID: "session", after: 12)

        XCTAssertEqual(store.value(sessionID: "session", key: "title"), .string("durable"))
        XCTAssertNil(store.value(sessionID: "session", key: "todo"))
    }
}
