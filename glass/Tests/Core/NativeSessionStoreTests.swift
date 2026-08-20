import XCTest

@testable import GlassCore

@MainActor
final class NativeSessionStoreTests: XCTestCase {
    func testComposerIntentUsesInjectedTypedSessionFacadeAndRetainsDraftOnRejection() async {
        let promptReachedFacade = expectation(description: "typed prompt facade receives the user intent")
        let api = RejectingSessionAPI(promptReachedFacade: promptReachedFacade)
        let store = NativeSessionStore()
        store.open(sessionID: "facade-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        store.draft = "do not bypass the typed facade"

        store.submitDraft()
        await fulfillment(of: [promptReachedFacade], timeout: 1)

        XCTAssertEqual(api.prompts.count, 1)
        XCTAssertEqual(api.prompts.first?.sessionID, "facade-session")
        guard case let .text(text)? = api.prompts.first?.content.first else {
            return XCTFail("composer did not pass a typed text content item to the facade")
        }
        XCTAssertEqual(text, "do not bypass the typed facade")
        XCTAssertEqual(store.draft, "do not bypass the typed facade", "a rejected typed facade call must retain the draft for retry")
    }

    func testCancelIntentUsesTypedFacadeOnlyForHostRunningTurn() async {
        let cancelReachedFacade = expectation(description: "typed cancel facade receives running turn intent")
        let api = RejectingSessionAPI(promptReachedFacade: nil, cancelReachedFacade: cancelReachedFacade)
        let store = NativeSessionStore()
        let sessionID = "cancel-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)

        store.cancelRunningTurn()
        XCTAssertTrue(api.cancelledSessionIDs.isEmpty, "idle composer must not manufacture a cancel RPC")

        store.applyMuxFrame(sessionEventFrame(
            sessionID: sessionID,
            seq: 1,
            type: "turn/start",
            data: .object(["turn": .number(1)])
        ), sessionID: sessionID)
        XCTAssertTrue(store.isRunning)

        store.cancelRunningTurn()
        await fulfillment(of: [cancelReachedFacade], timeout: 1)
        XCTAssertEqual(api.cancelledSessionIDs, [sessionID])
        XCTAssertTrue(store.isRunning, "carrier receipt cannot optimistically settle a Host-owned running turn")
    }

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
        store.selectView("future-plugin-view")
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
        XCTAssertEqual(store.selectedViewID, "future-plugin-view")
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
        XCTAssertEqual(store.items.last?.time, 500)
    }

    func testPendingApprovalAndQuestionClearOnlyOnMatchingHostResolution() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "approval-rpc", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"), "sessionId": .string("snapshot-tooling"), "approvalId": .string("approval-1"), "toolName": .string("bash"),
        ])), sessionID: "snapshot-tooling")
        XCTAssertEqual(store.pendingApproval?.rpcID, "approval-rpc")
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "wrong", method: "approval/resolved", payload: .object([
            "type": .string("approval/resolved"), "sessionId": .string("snapshot-tooling"), "approvalId": .string("other"),
        ])), sessionID: "snapshot-tooling")
        XCTAssertNotNil(store.pendingApproval)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "right", method: "approval/resolved", payload: .object([
            "type": .string("approval/resolved"), "sessionId": .string("snapshot-tooling"), "approvalId": .string("approval-1"),
        ])), sessionID: "snapshot-tooling")
        XCTAssertNil(store.pendingApproval)

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "question-rpc", method: "question/requested", payload: .object([
            "type": .string("question/requested"), "sessionId": .string("snapshot-tooling"),
            "questions": .array([.object(["id": .string("q-1"), "question": .string("Proceed?")])]),
        ])), sessionID: "snapshot-tooling")
        XCTAssertEqual(store.pendingQuestion?.rpcID, "question-rpc")
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "wrong", method: "question/resolved", payload: .object([
            "type": .string("question/resolved"), "sessionId": .string("snapshot-tooling"), "questionRpcId": .string("other"),
        ])), sessionID: "snapshot-tooling")
        XCTAssertNotNil(store.pendingQuestion)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "right", method: "question/resolved", payload: .object([
            "type": .string("question/resolved"), "sessionId": .string("snapshot-tooling"), "questionRpcId": .string("question-rpc"),
        ])), sessionID: "snapshot-tooling")
        XCTAssertNil(store.pendingQuestion)
    }

    func testReducerBackedJobsFixtureMatchesTranscriptAndStreamingFinalReusesSameNodeKey() {
        let store = NativeSessionStore()
        store.loadSnapshotJobsFixture()

        XCTAssertEqual(store.items.map(\.text), ["Reply with the single word LIGHTHOUSE and stop.", "LIGHTHOUSE"])
        let initialMessages = store.chatNodes.compactMap { $0.data as? CoreUserMessageNode }
        let initialAssistant = store.chatNodes.compactMap { $0.data as? CoreAssistantNode }
        XCTAssertEqual(initialMessages.map { $0.content.compactMap(\.text).joined() }, ["Reply with the single word LIGHTHOUSE and stop."])
        XCTAssertEqual(initialAssistant.map { $0.blocks.compactMap(\.text).joined() }, ["LIGHTHOUSE"])
        XCTAssertEqual(initialAssistant.first?.status, .settled)

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "fx-alpha",
            seq: 5,
            type: "turn/start",
            data: .object(["turn": .number(2)])
        ), sessionID: "fx-alpha")
        store.applyMuxFrame(sessionEventFrame(
            sessionID: "fx-alpha",
            seq: 6,
            type: "step/start",
            data: .object(["turn": .number(2), "step": .number(1)])
        ), sessionID: "fx-alpha")
        store.applyMuxFrame(sessionEventFrame(
            sessionID: "fx-alpha",
            seq: 7,
            type: "assistant/chunk",
            data: .object([
                "turn": .number(2),
                "step": .number(1),
                "chunk": .object(["type": .string("text-delta"), "index": .number(0), "text": .string("streaming")]),
            ])
        ), sessionID: "fx-alpha")

        guard let runningNode = store.chatNodes.first(where: { ($0.data as? CoreAssistantNode)?.turn == 2 }) else {
            return XCTFail("streaming assistant node was not materialized")
        }
        XCTAssertEqual((runningNode.data as? CoreAssistantNode)?.status, .running)
        XCTAssertEqual((runningNode.data as? CoreAssistantNode)?.blocks.compactMap(\.text).joined(), "streaming")

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "fx-alpha",
            seq: 8,
            type: "assistant/message",
            data: .object([
                "turn": .number(2),
                "step": .number(1),
                "message": .object([
                    "id": .string("final-turn-2-step-1"),
                    "content": .array([.object(["type": .string("text"), "text": .string("settled")])]),
                ]),
            ]),
            surfaceOp: "append"
        ), sessionID: "fx-alpha")

        let finalNodes = store.chatNodes.filter { ($0.data as? CoreAssistantNode)?.turn == 2 }
        XCTAssertEqual(finalNodes.map(\.key), [runningNode.key], "final evidence must settle the streaming row, not append a second node")
        XCTAssertEqual((finalNodes.first?.data as? CoreAssistantNode)?.status, .settled)
        XCTAssertEqual((finalNodes.first?.data as? CoreAssistantNode)?.blocks.compactMap(\.text).joined(), "settled")
    }

    func testSnapshotJobsFixtureUsesCurrentHostSessionAndWholeJobSet() {
        let store = NativeSessionStore()
        store.loadSnapshotJobsFixture()

        XCTAssertEqual(store.selectedSessionID, "fx-alpha")
        XCTAssertEqual(store.items.map(\.text), ["Reply with the single word LIGHTHOUSE and stop.", "LIGHTHOUSE"])
        XCTAssertEqual(store.backgroundJobs.map(\.id), ["bash-1", "bash-2"])
        XCTAssertEqual(store.backgroundJobs.map(\.status), [.running, .completed])
        XCTAssertEqual(store.backgroundJobs.map(\.label), ["sleep 60", "pnpm run build"])
        XCTAssertTrue(store.backgroundJobs[0].isLive)
        XCTAssertFalse(store.backgroundJobs[1].isLive)
        XCTAssertNil(store.pendingApproval)
        XCTAssertNil(store.pendingQuestion)
    }

    func testJobsPresentationUsesOfficialOrderingAndElapsedRules() {
        let jobs = [
            NativeSessionStore.BackgroundJob(id: "done-old", kind: "shell", label: "done-old", status: .completed, detail: nil, startedAt: 10, finishedAt: 20),
            NativeSessionStore.BackgroundJob(id: "running-late", kind: "shell", label: "running-late", status: .running, detail: nil, startedAt: 40, finishedAt: nil),
            NativeSessionStore.BackgroundJob(id: "stopping-early", kind: "shell", label: "stopping-early", status: .stopping, detail: nil, startedAt: 30, finishedAt: nil),
            NativeSessionStore.BackgroundJob(id: "failed-new", kind: "shell", label: "failed-new", status: .failed, detail: nil, startedAt: 15, finishedAt: 70),
        ]
        XCTAssertEqual(SessionJobsPresentation.ordered(jobs).map(\.id), ["stopping-early", "running-late", "failed-new", "done-old"])
        XCTAssertEqual(SessionJobsPresentation.elapsedMilliseconds(for: jobs[1], now: 100), 60)
        XCTAssertEqual(SessionJobsPresentation.elapsedMilliseconds(for: jobs[0], now: 100), 10)
    }

    @MainActor
    private final class RejectingSessionAPI: NativeSessionAPI {
        struct Prompt {
            let sessionID: String
            let content: [SessionPromptContent]
        }

        let promptReachedFacade: XCTestExpectation?
        let cancelReachedFacade: XCTestExpectation?
        private(set) var prompts: [Prompt] = []
        private(set) var cancelledSessionIDs: [String] = []

        init(promptReachedFacade: XCTestExpectation?, cancelReachedFacade: XCTestExpectation? = nil) {
            self.promptReachedFacade = promptReachedFacade
            self.cancelReachedFacade = cancelReachedFacade
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func prompt(sessionID: String, content: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse {
            prompts.append(.init(sessionID: sessionID, content: content))
            promptReachedFacade?.fulfill()
            throw DSHTransportError.invalidEndpoint
        }

        func cancel(sessionID: String) async throws -> SessionCancelResponse {
            cancelledSessionIDs.append(sessionID)
            cancelReachedFacade?.fulfill()
            throw DSHTransportError.invalidEndpoint
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt {
            throw DSHTransportError.invalidEndpoint
        }

        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt {
            throw DSHTransportError.invalidEndpoint
        }

        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt {
            throw DSHTransportError.invalidEndpoint
        }
    }

    private func sessionEventFrame(
        sessionID: String,
        seq: Int,
        type: String,
        data: JSONValue,
        surfaceOp: String? = nil
    ) -> RPCServerRequest {
        var event: [String: JSONValue] = [
            "type": .string(type),
            "seq": .number(Double(seq)),
            "time": .number(Double(seq)),
            "data": data,
        ]
        if let surfaceOp { event["surfaceOp"] = .string(surfaceOp) }
        return RPCServerRequest(
            type: "server-request",
            rpcId: "event-\(UUID().uuidString)",
            method: "session/event",
            payload: .object([
                "type": .string("session/event"),
                "sessionId": .string(sessionID),
                "event": .object(event),
            ])
        )
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
