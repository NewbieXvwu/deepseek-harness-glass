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

    func testGoalProjectionReaderUsesWholeHostValueAndTombstonesSafely() {
        let store = SessionProjectionStore()
        store.apply(sessionID: "session", key: "goal", value: goal(phase: "active"), seq: 20)
        store.apply(sessionID: "session", key: "goal", value: goal(phase: "complete"), seq: 19)

        let active = tryUnwrap(SessionGoalProjectionReader.value(from: store, sessionID: "session"))
        XCTAssertEqual(active.id, "goal-1")
        XCTAssertEqual(active.revision, 4)
        XCTAssertEqual(active.phase, .active)
        XCTAssertNil(active.blockedReason)

        store.apply(sessionID: "session", key: "goal", value: goal(phase: "blocked", reason: ["code": .string("awaiting-input"), "message": .string("Need user decision")]), seq: 21)
        let blocked = tryUnwrap(SessionGoalProjectionReader.value(from: store, sessionID: "session"))
        XCTAssertEqual(blocked.phase, .blocked)
        XCTAssertEqual(blocked.blockedReason, .init(code: "awaiting-input", message: "Need user decision"))

        store.apply(sessionID: "session", key: "goal", value: .null, seq: 22)
        XCTAssertNil(SessionGoalProjectionReader.value(from: store, sessionID: "session"))
    }

    func testGoalProjectionReaderRejectsMalformedOrInconsistentHostValues() {
        let store = SessionProjectionStore()
        store.apply(sessionID: "session", key: "goal", value: goal(phase: "active", reason: ["code": .string("invalid"), "message": .string("must be absent")]), seq: 1)
        XCTAssertNil(SessionGoalProjectionReader.value(from: store, sessionID: "session"))

        store.apply(sessionID: "session", key: "goal", value: goal(phase: "blocked"), seq: 2)
        XCTAssertNil(SessionGoalProjectionReader.value(from: store, sessionID: "session"))
    }

    private func goal(phase: String, reason: [String: JSONValue]? = nil) -> JSONValue {
        var goal: [String: JSONValue] = [
            "id": .string("goal-1"),
            "revision": .number(4),
            "objective": .string("Ship native implementation"),
            "phase": .string(phase),
            "maxGoalRounds": .number(8),
        ]
        if let reason { goal["blockedReason"] = .object(reason) }
        return .object([
            "goal": .object(goal),
            "roundsStarted": .number(3),
            "createdAt": .number(100),
            "updatedAt": .number(120),
        ])
    }

    private func tryUnwrap<T>(_ value: T?) -> T {
        guard let value else { fatalError("Expected non-nil value") }
        return value
    }
}
