import XCTest

@testable import GlassCore

@MainActor
final class NativeSessionStoreTests: XCTestCase {
    func testQueueAndJobsUseCompleteHostSnapshotsAndRejectOtherSessionFrames() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()

        store.applyMuxFrame(queueFrame(sessionID: "snapshot-tooling", items: [
            queuedItem(id: "q-1", messageID: "m-1", placement: "queued", content: [.object(["type": .string("text"), "text": .string("first queued turn")])]),
            queuedItem(id: "q-2", messageID: "m-2", placement: "steering", content: [.object(["type": .string("text"), "text": .string("steer now")])]),
        ]), sessionID: "snapshot-tooling")
        store.applyMuxFrame(jobsFrame(sessionID: "snapshot-tooling", jobs: [
            job(id: "job-1", status: "running", startedAt: 10),
        ]), sessionID: "snapshot-tooling")

        XCTAssertEqual(store.queuedMessages.map(\.id), ["q-1", "q-2"])
        XCTAssertEqual(store.queuedMessages.map(\.placement), [.queued, .steering])
        XCTAssertEqual(store.queuedMessages.first?.preview, "first queued turn")
        XCTAssertEqual(store.backgroundJobs.map(\.id), ["job-1"])
        XCTAssertTrue(store.backgroundJobs[0].isLive)

        // A second complete frame replaces rather than reconciles the prior set.
        store.applyMuxFrame(queueFrame(sessionID: "snapshot-tooling", items: [
            queuedItem(id: "q-3", messageID: "m-3", placement: "context", content: [.object(["type": .string("image")])]),
        ]), sessionID: "snapshot-tooling")
        store.applyMuxFrame(jobsFrame(sessionID: "snapshot-tooling", jobs: []), sessionID: "snapshot-tooling")
        store.applyMuxFrame(queueFrame(sessionID: "other", items: [
            queuedItem(id: "foreign", messageID: "foreign", placement: "queued", content: []),
        ]), sessionID: "snapshot-tooling")

        XCTAssertEqual(store.queuedMessages.map(\.id), ["q-3"])
        XCTAssertEqual(store.queuedMessages.first?.preview, "[image]")
        XCTAssertNil(store.queuedMessages.first?.text)
        XCTAssertTrue(store.backgroundJobs.isEmpty)
    }

    func testSubscriptionClearsPriorGenerationTransientStateAndTruncatesProjection() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.projections.apply(sessionID: "snapshot-tooling", key: "title", value: .string("durable"), seq: 12)
        store.projections.apply(sessionID: "snapshot-tooling", key: "todo", value: .string("lost-on-restart"), seq: 15)
        store.applyMuxFrame(queueFrame(sessionID: "snapshot-tooling", items: [
            queuedItem(id: "q-1", messageID: "m-1", placement: "queued", content: []),
        ]), sessionID: "snapshot-tooling")
        store.applyMuxFrame(jobsFrame(sessionID: "snapshot-tooling", jobs: [job(id: "job-1", status: "completed", startedAt: 1)]), sessionID: "snapshot-tooling")

        store.applyMuxFrame(RPCServerRequest(
            type: "server-request",
            rpcId: "subscribed-1",
            method: "session/subscribed",
            payload: .object([
                "type": .string("session/subscribed"),
                "sessionId": .string("snapshot-tooling"),
                "lastSeq": .number(12),
            ])
        ), sessionID: "snapshot-tooling")

        XCTAssertTrue(store.queuedMessages.isEmpty)
        XCTAssertTrue(store.backgroundJobs.isEmpty)
        XCTAssertEqual(store.projections.value(sessionID: "snapshot-tooling", key: "title"), .string("durable"))
        XCTAssertNil(store.projections.value(sessionID: "snapshot-tooling", key: "todo"))
    }

    func testResidentWindowRestoreRetainsSelectionToolsAndTransientHostStateAcrossSessionSwitch() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.selectToolCall("snapshot-bash")
        store.applyMuxFrame(queueFrame(sessionID: "snapshot-tooling", items: [
            queuedItem(id: "q-1", messageID: "m-1", placement: "steering", content: [.object(["type": .string("text"), "text": .string("retain me")])]),
        ]), sessionID: "snapshot-tooling")
        store.applyMuxFrame(jobsFrame(sessionID: "snapshot-tooling", jobs: [job(id: "job-1", status: "stopping", startedAt: 1)]), sessionID: "snapshot-tooling")
        store.preserveActiveState()

        store.loadSnapshotQuestionFixture()
        XCTAssertTrue(store.restoreResidentState(for: "snapshot-tooling"))

        XCTAssertEqual(store.items.map(\.id), ["event-101", "event-104"])
        XCTAssertEqual(store.toolInvocations.map(\.id), ["snapshot-read", "snapshot-bash"])
        XCTAssertEqual(store.selectedToolCallID, "snapshot-bash")
        XCTAssertEqual(store.queuedMessages.first?.preview, "retain me")
        XCTAssertEqual(store.backgroundJobs.first?.status, .stopping)
    }

    func testDurableUserMessageRetiresOnlyMatchingTransientSteeringRow() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.applyMuxFrame(queueFrame(sessionID: "snapshot-tooling", items: [
            queuedItem(id: "queued", messageID: "ordinary", placement: "queued", content: [.object(["type": .string("text"), "text": .string("keep me")])]),
            queuedItem(id: "steering", messageID: "steer-me", placement: "steering", content: [.object(["type": .string("text"), "text": .string("retire me")])]),
        ]), sessionID: "snapshot-tooling")

        store.applyMuxFrame(eventFrame(sessionID: "snapshot-tooling", seq: 500, messageID: "steer-me", text: "admitted steering"), sessionID: "snapshot-tooling")

        XCTAssertEqual(store.queuedMessages.map(\.id), ["queued"])
        XCTAssertEqual(store.queuedMessages.first?.messageID, "ordinary")
        XCTAssertEqual(store.items.last?.text, "admitted steering")
    }

    private func eventFrame(sessionID: String, seq: Int, messageID: String, text: String) -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: "event-\(UUID().uuidString)",
            method: "session/event",
            payload: .object([
                "type": .string("session/event"),
                "sessionId": .string(sessionID),
                "event": .object([
                    "type": .string("user/message"),
                    "seq": .number(Double(seq)),
                    "time": .number(Double(seq)),
                    "surfaceOp": .string("append"),
                    "data": .object([
                        "id": .string(messageID),
                        "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                        "source": .object(["kind": .string("user")]),
                    ]),
                ]),
            ]))
    }

    private func queueFrame(sessionID: String, items: [JSONValue]) -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: "queue-\(UUID().uuidString)",
            method: "session/queue",
            payload: .object([
                "type": .string("session/queue"),
                "sessionId": .string(sessionID),
                "items": .array(items),
            ])
        )
    }

    private func queuedItem(id: String, messageID: String, placement: String, content: [JSONValue]) -> JSONValue {
        .object([
            "id": .string(id),
            "placement": .string(placement),
            "message": .object([
                "id": .string(messageID),
                "role": .string("user"),
                "content": .array(content),
                "source": .object(["kind": .string("user")]),
            ]),
        ])
    }

    private func jobsFrame(sessionID: String, jobs: [JSONValue]) -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: "jobs-\(UUID().uuidString)",
            method: "session/jobs",
            payload: .object([
                "type": .string("session/jobs"),
                "sessionId": .string(sessionID),
                "jobs": .array(jobs),
            ])
        )
    }

    private func job(id: String, status: String, startedAt: Int) -> JSONValue {
        .object([
            "id": .string(id),
            "kind": .string("shell"),
            "label": .string("Run shell task"),
            "status": .string(status),
            "startedAt": .number(Double(startedAt)),
        ])
    }
}
