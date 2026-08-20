import XCTest
import GlassSpec
@testable import GlassPortableCore
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

    func testAcceptedPromptClearsDraftOnlyAfterTypedHostFacadeAcceptance() async {
        let promptReachedFacade = expectation(description: "typed prompt facade returns Host acceptance")
        let api = AcceptingSessionAPI(promptReachedFacade: promptReachedFacade)
        let store = NativeSessionStore()
        let sessionID = "accepted-prompt-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        store.draft = "preserve until the Host accepts"

        store.submitDraft()
        XCTAssertEqual(store.draft, "preserve until the Host accepts")
        await fulfillment(of: [promptReachedFacade], timeout: 1)
        await eventually(timeout: 1) { store.draft.isEmpty }
        XCTAssertEqual(api.promptSessionIDs, [sessionID])
    }

    func testInitialAuthorityFromReplacedEndpointCannotReviveOldColdState() async {
        let oldModelsReached = expectation(description: "old endpoint reaches delayed initial models read")
        let oldAPI = GatedInitialModelsAPI(modelsReached: oldModelsReached)
        let store = NativeSessionStore()
        let oldEndpoint = URL(string: "http://127.0.0.1:1")!
        let replacementEndpoint = URL(string: "http://127.0.0.1:2")!
        store.open(sessionID: "same-session", using: oldAPI, endpoint: oldEndpoint)
        await fulfillment(of: [oldModelsReached], timeout: 1)

        // The first typed facade is non-cooperative: it completes only after
        // cancellation and the replacement endpoint have already become live.
        store.open(sessionID: "same-session", using: RejectingSessionAPI(promptReachedFacade: nil), endpoint: replacementEndpoint)
        await oldAPI.releaseModels()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(store.selectedSessionID, "same-session")
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.modelDirectory)
        XCTAssertNil(store.extensionState?.modelDirectory)
        XCTAssertTrue(store.extensionState?.queuedMessages.isEmpty == true)
        XCTAssertTrue(store.extensionState?.backgroundJobs.isEmpty == true)
    }

    func testCancelledRecoveryCannotReviveDisconnectedSession() async {
        let recoveryReachedModels = expectation(description: "recovery reaches delayed models read")
        let api = GatedGapRecoveryAPI(recoveryReachedModels: recoveryReachedModels)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("must not append")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedModels], timeout: 1)

        store.disconnect()
        await api.releaseDelayedModels()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertNil(store.selectedSessionID)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.modelDirectory)
        XCTAssertNil(store.extensionState)
    }

    func testClearActiveSelectionRetainsResidentSessionForLaterReopen() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let originalItemIDs = store.items.map(\.id)
        XCTAssertEqual(store.selectedSessionID, "snapshot-tooling")

        store.clearActiveSelection()

        XCTAssertNil(store.selectedSessionID)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.modelDirectory)
        XCTAssertNil(store.extensionState)
        XCTAssertTrue(store.restoreResidentState(for: "snapshot-tooling"))
        XCTAssertEqual(store.items.map(\.id), originalItemIDs)
    }

    func testSubscriptionWatermarkRollbackRecoversFullAuthorityWindow() async {
        let recoveryReachedHistory = expectation(description: "watermark rollback triggers authority history")
        let api = GapRecoveringSessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "restart-subscription", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string("recovery-session"),
            "lastSeq": .number(0),
        ])), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline", "recovered authority"] }
        XCTAssertEqual(store.items.map(\.sequence), [1, 2])
    }

    func testLiveEventGapRecoversFullAuthorityWindowInsteadOfAppendingDiscontinuousTail() async {
        let recoveryReachedHistory = expectation(description: "gap triggers a second authority history read")
        let api = GapRecoveringSessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("must not append")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline", "recovered authority"] }

        XCTAssertEqual(store.items.map(\.sequence), [1, 2])
        XCTAssertFalse(store.items.contains(where: { $0.text == "must not append" }))
        XCTAssertEqual(store.chatNodes.compactMap { $0.data as? CoreUserMessageNode }.map(\.seq), [1, 2])
    }

    func testSessionModelsAuthorityPublishesTypedDirectoryAndClearsForColdSession() async {
        let modelsLoaded = expectation(description: "session.models reaches typed facade")
        let api = ModelDirectorySessionAPI(modelsLoaded: modelsLoaded)
        let store = NativeSessionStore()
        store.open(sessionID: "models-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await fulfillment(of: [modelsLoaded], timeout: 1)
        await eventually(timeout: 1) { store.modelDirectory != nil }

        let directory = tryUnwrap(store.modelDirectory)
        XCTAssertTrue(directory.routable)
        XCTAssertEqual(directory.current, .init(provider: "provider-a", model: "model-a", reasoningEffort: "balanced"))
        XCTAssertTrue(directory.contains(provider: "provider-a", model: "model-a"))
        XCTAssertFalse(directory.contains(provider: "failed-provider", model: "invented"))
        XCTAssertEqual(directory.failures.map(\.id), ["failed-provider"])
        XCTAssertEqual(store.extensionState?.modelDirectory, directory)

        store.open(
            sessionID: "cold-session",
            using: RejectingSessionAPI(promptReachedFacade: nil),
            endpoint: URL(string: "http://127.0.0.1:1")!
        )
        XCTAssertNil(store.modelDirectory)
        XCTAssertNil(store.extensionState?.modelDirectory)
    }

    func testKnownProjectPathUsesHostFacadeAfterSessionCWDResolutionAndRejectsURLs() async {
        let opened = expectation(description: "recognized project token reaches typed Host facade")
        let hostPathAPI = RecordingHostPathAPI(opened: opened)
        let store = NativeSessionStore()
        store.open(
            sessionID: "path-session",
            using: RejectingSessionAPI(promptReachedFacade: nil),
            endpoint: URL(string: "http://127.0.0.1:1")!,
            hostPathAPI: hostPathAPI,
            sessionCWD: "/workspace/project"
        )

        store.openKnownProjectPath("src/main.swift")
        await fulfillment(of: [opened], timeout: 1)
        XCTAssertEqual(hostPathAPI.paths, ["/workspace/project/src/main.swift"])

        store.openKnownProjectPath("file:///etc/passwd")
        store.openKnownProjectPath("https://example.invalid/a.swift")
        store.openKnownProjectPath(" ")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(hostPathAPI.paths, ["/workspace/project/src/main.swift"])

        XCTAssertEqual(NativeProjectPathResolver.resolve(cwd: "/workspace/project/", path: "/tmp/absolute.txt"), "/tmp/absolute.txt")
        XCTAssertEqual(NativeProjectPathResolver.resolve(cwd: "/workspace/project", path: "C:\\code\\main.swift"), "C:\\code\\main.swift")
        XCTAssertEqual(NativeProjectPathResolver.resolve(cwd: "/workspace/project///", path: #"\notes\\todo.md"#), "/workspace/project/notes\\\\todo.md")
        XCTAssertEqual(NativeProjectPathResolver.resolve(cwd: "///", path: #"\child"#), "/child")
        XCTAssertEqual(NativeProjectPathResolver.resolve(cwd: "/workspace/project\\\\", path: ""), "/workspace/project/")
    }

    func testSnapshotTodoFixtureUsesOnlyHostWholeListProjection() {
        let store = NativeSessionStore()
        store.loadSnapshotTodoFixture()

        XCTAssertEqual(store.selectedSessionID, "snapshot-tooling")
        XCTAssertFalse(store.isRunning)
        XCTAssertNil(store.selectedToolCallID)
        XCTAssertEqual(store.extensionState?.todos, [
            .init(content: "Inspect the project instructions", status: .completed),
            .init(content: "Implement the native todo dock", status: .inProgress),
            .init(content: "Run the paired visual review", status: .pending),
        ])
    }

    func testExtensionStateJoinsOnlyTypedActiveSessionAuthoritiesAndFailsClosedForMalformedTodos() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = "snapshot-tooling"
        store.projections.apply(sessionID: sessionID, key: "todos", value: .array([
            .object(["content": .string("inspect result"), "status": .string("in_progress")]),
            .object(["content": .string("ship"), "status": .string("completed")]),
        ]), seq: 10)
        store.projections.apply(sessionID: sessionID, key: "goal", value: .object([
            "goal": .object([
                "id": .string("goal-1"), "revision": .number(1), "objective": .string("Release safely"),
                "phase": .string("active"), "maxGoalRounds": .number(4),
            ]),
            "roundsStarted": .number(1), "createdAt": .number(100), "updatedAt": .number(101),
        ]), seq: 11)
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-1", messageID: "m-1", placement: "steering", content: [.object(["type": .string("text"), "text": .string("answer now")])]),
        ]), sessionID: sessionID)
        store.applyMuxFrame(jobsFrame(sessionID: sessionID, jobs: [job(id: "job-1", status: "running", startedAt: 10)]), sessionID: sessionID)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "approval-rpc", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"), "sessionId": .string(sessionID), "approvalId": .string("approval-1"), "toolName": .string("bash"),
        ])), sessionID: sessionID)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "question-rpc", method: "question/requested", payload: .object([
            "type": .string("question/requested"), "sessionId": .string(sessionID),
            "questions": .array([.object(["id": .string("question-1"), "question": .string("Proceed?")])]),
        ])), sessionID: sessionID)

        let state = tryUnwrap(store.extensionState)
        XCTAssertEqual(state.todos?.map(\.status), [.inProgress, .completed])
        XCTAssertEqual(state.goal?.id, "goal-1")
        XCTAssertEqual(state.goal?.phase, .active)
        XCTAssertEqual(state.queuedMessages.map(\.id), ["q-1"])
        XCTAssertEqual(state.backgroundJobs.map(\.id), ["job-1"])
        XCTAssertEqual(state.pendingApproval?.rpcID, "approval-rpc")
        XCTAssertEqual(state.pendingQuestion?.rpcID, "question-rpc")
        XCTAssertEqual(state.subagentIdentity, CoreSubagentIdentityProjection.absent)
        XCTAssertNil(state.subagentTiming)

        // A later malformed whole todo projection cannot leak a partly decoded
        // local plan into any extension renderer.
        store.projections.apply(sessionID: sessionID, key: "todos", value: .array([
            .object(["content": .string("duplicate"), "status": .string("pending")]),
            .object(["content": .string("duplicate"), "status": .string("completed")]),
        ]), seq: 12)
        XCTAssertNil(store.extensionState?.todos)

        // Changing the active Host session must never reuse extension state from
        // a resident predecessor while the new authority baseline is loading.
        store.open(
            sessionID: "fresh-session",
            using: RejectingSessionAPI(promptReachedFacade: nil),
            endpoint: URL(string: "http://127.0.0.1:1")!
        )
        let freshState = tryUnwrap(store.extensionState)
        XCTAssertNil(freshState.todos)
        XCTAssertNil(freshState.goal)
        XCTAssertTrue(freshState.queuedMessages.isEmpty)
        XCTAssertTrue(freshState.backgroundJobs.isEmpty)
        XCTAssertNil(freshState.pendingApproval)
        XCTAssertNil(freshState.pendingQuestion)
        XCTAssertEqual(freshState.subagentIdentity, CoreSubagentIdentityProjection.absent)
        XCTAssertNil(freshState.subagentTiming)
    }

    func testSubagentProjectionReaderPreservesNullSentinelAndRejectsMalformedIdentityOrTiming() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = "snapshot-tooling"
        XCTAssertEqual(SessionSubagentProjectionReader.identity(from: store.projections, sessionID: sessionID), .absent)

        store.projections.apply(sessionID: sessionID, key: "subagent", value: .null, seq: 1)
        XCTAssertEqual(SessionSubagentProjectionReader.identity(from: store.projections, sessionID: sessionID), .noValidDescriptor)
        store.projections.apply(sessionID: sessionID, key: "subagent", value: .object([
            "mode": .string("continuable"), "label": .string(""), "seq": .number(2),
        ]), seq: 2)
        XCTAssertEqual(SessionSubagentProjectionReader.identity(from: store.projections, sessionID: sessionID), .noValidDescriptor)
        store.projections.apply(sessionID: sessionID, key: "subagent", value: .object([
            "mode": .string("continuable"), "label": .string("review"), "seq": .number(3),
        ]), seq: 3)
        XCTAssertEqual(SessionSubagentProjectionReader.identity(from: store.projections, sessionID: sessionID), .identity(.init(mode: .continuable, label: "review", descriptorSeq: 3)))

        store.projections.apply(sessionID: sessionID, key: "subagentTiming", value: .object([
            "settledMs": .number(40), "active": .object(["since": .number(100), "through": .number(120)]),
        ]), seq: 4)
        XCTAssertEqual(SessionSubagentProjectionReader.timing(from: store.projections, sessionID: sessionID), .init(settledMilliseconds: 40, active: .init(since: 100, through: 120)))
        store.projections.apply(sessionID: sessionID, key: "subagentTiming", value: .object([
            "settledMs": .number(40), "active": .object(["since": .number(121), "through": .number(120)]),
        ]), seq: 5)
        XCTAssertNil(SessionSubagentProjectionReader.timing(from: store.projections, sessionID: sessionID))
    }

    func testMuxFramesForNonActiveSessionCannotPolluteExtensionState() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.applyMuxFrame(queueFrame(sessionID: "foreign", items: [
            queuedItem(id: "foreign-queue", messageID: "foreign-message", placement: "queued", content: []),
        ]), sessionID: "foreign")
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "foreign-approval", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"), "sessionId": .string("foreign"),
            "approvalId": .string("foreign-approval"), "toolName": .string("bash"),
        ])), sessionID: "foreign")

        let state = tryUnwrap(store.extensionState)
        XCTAssertTrue(state.queuedMessages.isEmpty)
        XCTAssertNil(state.pendingApproval)
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

    func testSubscriptionGenerationClearsPendingInteractionTakeoversAlongsideQueueAndJobs() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = "snapshot-tooling"
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-1", messageID: "m-1", placement: "queued", content: []),
        ]), sessionID: sessionID)
        store.applyMuxFrame(jobsFrame(sessionID: sessionID, jobs: [job(id: "job-1", status: "running", startedAt: 1)]), sessionID: sessionID)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "approval-rpc", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"), "sessionId": .string(sessionID), "approvalId": .string("approval-1"), "toolName": .string("bash"),
        ])), sessionID: sessionID)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "question-rpc", method: "question/requested", payload: .object([
            "type": .string("question/requested"), "sessionId": .string(sessionID),
            "questions": .array([.object(["id": .string("q-1"), "question": .string("Proceed?")])]),
        ])), sessionID: sessionID)
        XCTAssertNotNil(store.extensionState?.pendingApproval)
        XCTAssertNotNil(store.extensionState?.pendingQuestion)

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "subscribed-2", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"), "sessionId": .string(sessionID), "lastSeq": .number(0),
        ])), sessionID: sessionID)

        let state = tryUnwrap(store.extensionState)
        XCTAssertTrue(state.queuedMessages.isEmpty)
        XCTAssertTrue(state.backgroundJobs.isEmpty)
        XCTAssertNil(state.pendingApproval)
        XCTAssertNil(state.pendingQuestion)
        XCTAssertFalse(store.isSubmittingApproval)
        XCTAssertFalse(store.isSubmittingQuestion)
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

        // `loadSnapshotToolingFixture` ends at sequence 104. Use the next
        // contiguous Host event so this test exercises steering retirement,
        // rather than correctly triggering the T6.7 gap-recovery fence.
        store.applyMuxFrame(eventFrame(sessionID: "snapshot-tooling", seq: 105, messageID: "steer-me", text: "admitted steering"), sessionID: "snapshot-tooling")

        XCTAssertEqual(store.queuedMessages.map(\.id), ["queued"])
        XCTAssertEqual(store.queuedMessages.first?.messageID, "ordinary")
        XCTAssertEqual(store.items.last?.text, "admitted steering")
        XCTAssertEqual(store.items.last?.time, 105)
    }

    func testQuestionRequestPreservesOfficialPlanReviewIntentAndRejectsUnknownIntent() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = "snapshot-tooling"
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "plan-review-rpc", method: "question/requested", payload: .object([
            "type": .string("question/requested"), "sessionId": .string(sessionID),
            "questions": .array([.object([
                "id": .string("review"), "question": .string("Approve the plan?"),
                "intent": .object(["kind": .string("plan-review"), "approve": .string("Approve plan")]),
            ])]),
        ])), sessionID: sessionID)
        XCTAssertEqual(store.pendingQuestion?.rpcID, "plan-review-rpc")
        XCTAssertEqual(store.pendingQuestion?.items.first?.intent, .planReview(approve: "Approve plan"))

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "unknown-intent-rpc", method: "question/requested", payload: .object([
            "type": .string("question/requested"), "sessionId": .string(sessionID),
            "questions": .array([.object([
                "id": .string("bad"), "question": .string("Unsupported?"),
                "intent": .object(["kind": .string("future-intent")]),
            ])]),
        ])), sessionID: sessionID)
        XCTAssertEqual(store.pendingQuestion?.rpcID, "plan-review-rpc")
        XCTAssertEqual(store.pendingQuestion?.items.first?.intent, .planReview(approve: "Approve plan"))
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

    private func eventually(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition was not met before timeout")
    }

    @MainActor
    private final class AcceptingSessionAPI: NativeSessionAPI {
        let promptReachedFacade: XCTestExpectation
        private(set) var promptSessionIDs: [String] = []

        init(promptReachedFacade: XCTestExpectation) {
            self.promptReachedFacade = promptReachedFacade
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse { throw DSHTransportError.invalidEndpoint }
        func models(sessionID _: String) async throws -> SessionModelsResponse { throw DSHTransportError.invalidEndpoint }
        func prompt(sessionID: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse {
            promptSessionIDs.append(sessionID)
            promptReachedFacade.fulfill()
            return SessionPromptResponse(accepted: true)
        }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class GatedInitialModelsAPI: NativeSessionAPI {
        let modelsReached: XCTestExpectation
        private let modelsGate = RecoveryGate()

        init(modelsReached: XCTestExpectation) {
            self.modelsReached = modelsReached
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsReached.fulfill()
            await modelsGate.wait()
            return .init(current: .init(provider: "stale-provider", model: "stale-model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [], hasMore: false, projections: nil)
        }

        func releaseModels() async { await modelsGate.open() }
        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class GatedGapRecoveryAPI: NativeSessionAPI {
        let recoveryReachedModels: XCTestExpectation
        private let modelsGate = RecoveryGate()
        private var modelsCount = 0
        private var historyCount = 0

        init(recoveryReachedModels: XCTestExpectation) {
            self.recoveryReachedModels = recoveryReachedModels
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCount += 1
            return .init(events: [historyEntry(seq: 1, id: "baseline", text: "baseline")], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsCount += 1
            if modelsCount > 1 {
                recoveryReachedModels.fulfill()
                await modelsGate.wait()
            }
            return .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func releaseDelayedModels() async { await modelsGate.open() }
        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }

        private func historyEntry(seq: Int, id: String, text: String) -> SessionHistoryEntryDTO {
            .init(event: .init(
                type: "user/message", seq: seq, time: Double(seq),
                data: .object([
                    "id": .string(id),
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: .string("append"), sourceEventSeqs: nil, ignorable: nil
            ), view: nil)
        }
    }

    @MainActor
    private final class GapRecoveringSessionAPI: NativeSessionAPI {
        let recoveryReachedHistory: XCTestExpectation
        private var historyCount = 0

        init(recoveryReachedHistory: XCTestExpectation) {
            self.recoveryReachedHistory = recoveryReachedHistory
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCount += 1
            if historyCount > 1 { recoveryReachedHistory.fulfill() }
            let first = historyEntry(seq: 1, id: "baseline", text: "baseline")
            if historyCount == 1 {
                return .init(events: [first], hasMore: false, projections: nil)
            }
            return .init(
                events: [first, historyEntry(seq: 2, id: "recovered", text: "recovered authority")],
                hasMore: false,
                projections: nil
            )
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }

        private func historyEntry(seq: Int, id: String, text: String) -> SessionHistoryEntryDTO {
            .init(event: .init(
                type: "user/message",
                seq: seq,
                time: Double(seq),
                data: .object([
                    "id": .string(id),
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: .string("append"),
                sourceEventSeqs: nil,
                ignorable: nil
            ), view: nil)
        }
    }

    @MainActor
    private final class ModelDirectorySessionAPI: NativeSessionAPI {
        let modelsLoaded: XCTestExpectation

        init(modelsLoaded: XCTestExpectation) {
            self.modelsLoaded = modelsLoaded
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsLoaded.fulfill()
            return .init(
                current: .init(provider: "provider-a", model: "model-a", reasoningEffort: "balanced"),
                routable: true,
                groups: [.init(id: "provider-a", name: "Provider A", models: [
                    .init(id: "model-a", name: "Model A", description: "safe", reasoning: .init(
                        efforts: [.init(id: "balanced", name: "Balanced", description: nil)],
                        defaultEffort: "balanced"
                    ))
                ])],
                failures: [.init(id: "failed-provider", name: "Failed provider", message: "catalog unavailable")]
            )
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
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

    @MainActor
    private final class RecordingHostPathAPI: NativeHostPathAPI {
        let opened: XCTestExpectation
        private(set) var paths: [String] = []

        init(opened: XCTestExpectation) {
            self.opened = opened
        }

        func openPath(_ path: String) async throws -> HostOpenPathResponse {
            paths.append(path)
            opened.fulfill()
            return HostOpenPathResponse(opened: true)
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

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected non-nil value", file: file, line: line)
            fatalError("Expected non-nil value")
        }
        return value
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
