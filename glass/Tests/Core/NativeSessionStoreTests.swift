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

    func testMessageFeedbackPublishesCompleteHostSnapshotAndFailsClosed() async {
        let reached = expectation(description: "feedback list reaches typed Host facade")
        let initial = MessageFeedbackListResponse(
            ok: true,
            value: .init(items: [
                .init(messageId: "assistant-1", rating: .positive, note: "useful", version: "v1", createdAt: 1, updatedAt: 1),
            ]),
            error: nil
        )
        let feedbackAPI = RecordingMessageFeedbackAPI(response: initial, reached: reached)
        let store = NativeSessionStore()
        let sessionAPI = RejectingSessionAPI(promptReachedFacade: nil)
        store.open(sessionID: "feedback-session", using: sessionAPI, endpoint: URL(string: "http://127.0.0.1:1")!)
        XCTAssertFalse(store.isMessageFeedbackAvailable)
        store.setMessageFeedbackAPIForTesting(feedbackAPI)
        XCTAssertTrue(store.isMessageFeedbackAvailable)
        store.refreshMessageFeedback()
        await fulfillment(of: [reached], timeout: 1)
        await eventually(timeout: 1) { store.messageFeedbackItems["assistant-1"]?.version == "v1" && !store.isLoadingMessageFeedback }
        XCTAssertFalse(store.failedMessageFeedbackLoad)

        feedbackAPI.response = .init(
            ok: false,
            value: nil,
            error: .init(code: "session-not-found", sessionId: "feedback-session", messageId: nil, current: nil, maxBytes: nil, actualBytes: nil)
        )
        let failed = expectation(description: "failed feedback list reaches typed Host facade")
        feedbackAPI.reached = failed
        store.refreshMessageFeedback()
        await fulfillment(of: [failed], timeout: 1)
        await eventually(timeout: 1) { store.failedMessageFeedbackLoad && store.messageFeedbackItems.isEmpty && !store.isLoadingMessageFeedback }
    }

    func testAuthorityRecoveryResyncsMessageFeedbackFromLatestHostList() async {
        let feedbackLists = expectation(description: "initial and recovered feedback lists reach Host")
        feedbackLists.expectedFulfillmentCount = 2
        let recoveryHistory = expectation(description: "event gap reaches authority history recovery")
        let initialFeedback = MessageFeedbackListResponse(
            ok: true,
            value: .init(items: [
                .init(messageId: "assistant-1", rating: .positive, note: "initial", version: "v1", createdAt: 1, updatedAt: 1),
            ]),
            error: nil
        )
        let feedbackAPI = RecordingMessageFeedbackAPI(response: initialFeedback, reached: feedbackLists)
        let sessionAPI = GapRecoveringSessionAPI(recoveryReachedHistory: recoveryHistory)
        let store = NativeSessionStore()
        store.open(
            sessionID: "recovery-session",
            using: sessionAPI,
            endpoint: URL(string: "http://127.0.0.1:1")!,
            messageFeedbackAPI: feedbackAPI
        )
        await eventually(timeout: 1) { store.messageFeedbackItems["assistant-1"]?.version == "v1" }

        feedbackAPI.response = .init(
            ok: true,
            value: .init(items: [
                .init(messageId: "assistant-1", rating: .negative, note: "recovered", version: "v2", createdAt: 1, updatedAt: 2),
            ]),
            error: nil
        )
        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("feedback-gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("trigger authority recovery")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryHistory, feedbackLists], timeout: 1)
        await eventually(timeout: 1) {
            store.messageFeedbackItems["assistant-1"]?.version == "v2"
                && store.messageFeedbackItems["assistant-1"]?.rating == .negative
        }

        XCTAssertEqual(feedbackAPI.sessionIDs, ["recovery-session", "recovery-session"])
        XCTAssertEqual(store.messageFeedbackItems["assistant-1"]?.note, "recovered")
        XCTAssertFalse(store.failedMessageFeedbackLoad)
    }

    func testRecoveryFeedbackResyncWaitsForCommittedSameSessionMutation() async {
        let feedbackLists = expectation(description: "initial and post-mutation feedback lists reach Host")
        feedbackLists.expectedFulfillmentCount = 2
        let mutationReached = expectation(description: "feedback mutation reaches Host before recovery resync")
        let recoveryHistory = expectation(description: "gap recovery reaches authority history")
        let feedbackAPI = GatedRecoveryFeedbackAPI(
            listResponse: .init(
                ok: true,
                value: .init(items: [
                    .init(messageId: "assistant-1", rating: .positive, note: "initial", version: "v1", createdAt: 1, updatedAt: 1),
                ]),
                error: nil
            ),
            listReached: feedbackLists,
            mutationReached: mutationReached
        )
        let store = NativeSessionStore()
        store.open(
            sessionID: "recovery-session",
            using: GapRecoveringSessionAPI(recoveryReachedHistory: recoveryHistory),
            endpoint: URL(string: "http://127.0.0.1:1")!,
            messageFeedbackAPI: feedbackAPI
        )
        await eventually(timeout: 1) { store.messageFeedbackItems["assistant-1"]?.version == "v1" }

        store.toggleMessageFeedback(messageID: "assistant-1", rating: .negative)
        await fulfillment(of: [mutationReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingMessageFeedback)

        feedbackAPI.listResponse = .init(
            ok: true,
            value: .init(items: [
                .init(messageId: "assistant-1", rating: .negative, note: "resynced", version: "v3", createdAt: 1, updatedAt: 3),
            ]),
            error: nil
        )
        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("mutation-recovery-gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("trigger recovery")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryHistory], timeout: 1)
        XCTAssertEqual(feedbackAPI.sessionIDs.count, 1, "resync must wait behind the admitted mutation")

        await feedbackAPI.releaseMutation()
        await fulfillment(of: [feedbackLists], timeout: 1)
        await eventually(timeout: 1) {
            store.messageFeedbackItems["assistant-1"]?.version == "v3" && !store.isSubmittingMessageFeedback
        }

        XCTAssertEqual(feedbackAPI.putRequests.first?.ifVersion, "v1")
        XCTAssertEqual(feedbackAPI.sessionIDs, ["recovery-session", "recovery-session"])
        XCTAssertEqual(store.messageFeedbackItems["assistant-1"]?.note, "resynced")
    }

    func testMessageFeedbackMutationUsesCommittedVersionAndReconcilesConflict() async {
        let reached = expectation(description: "feedback seed reaches typed Host facade")
        let initial = MessageFeedbackListResponse(
            ok: true,
            value: .init(items: [
                .init(messageId: "assistant-1", rating: .positive, note: "keep", version: "v1", createdAt: 1, updatedAt: 1),
            ]),
            error: nil
        )
        let feedbackAPI = RecordingMessageFeedbackAPI(response: initial, reached: reached)
        feedbackAPI.putResponse = .init(
            ok: true,
            value: .init(messageId: "assistant-1", rating: .negative, note: "keep", version: "v2", createdAt: 1, updatedAt: 2),
            error: nil
        )
        let store = NativeSessionStore()
        store.open(sessionID: "feedback-mutation", using: RejectingSessionAPI(promptReachedFacade: nil), endpoint: URL(string: "http://127.0.0.1:1")!)
        store.setMessageFeedbackAPIForTesting(feedbackAPI)
        store.refreshMessageFeedback()
        await fulfillment(of: [reached], timeout: 1)
        await eventually(timeout: 1) { store.messageFeedbackItems["assistant-1"]?.version == "v1" }

        store.toggleMessageFeedback(messageID: "assistant-1", rating: .negative)
        await eventually(timeout: 1) { feedbackAPI.putRequests.count == 1 && store.messageFeedbackItems["assistant-1"]?.version == "v2" }
        XCTAssertEqual(feedbackAPI.putRequests.first?.ifVersion, "v1")
        XCTAssertEqual(feedbackAPI.putRequests.first?.note, "keep")
        XCTAssertNil(store.messageFeedbackActionFailureCode)

        feedbackAPI.putResponse = .init(
            ok: false,
            value: nil,
            error: .init(
                code: "version-conflict",
                sessionId: "feedback-mutation",
                messageId: "assistant-1",
                current: .init(messageId: "assistant-1", rating: .positive, note: "remote", version: "v3", createdAt: 1, updatedAt: 3),
                maxBytes: nil,
                actualBytes: nil
            )
        )
        store.toggleMessageFeedback(messageID: "assistant-1", rating: .positive)
        await eventually(timeout: 1) { feedbackAPI.putRequests.count == 2 && store.messageFeedbackItems["assistant-1"]?.version == "v3" }
        XCTAssertEqual(store.messageFeedbackActionFailureCode, "version-conflict")
        XCTAssertEqual(store.messageFeedbackItems["assistant-1"]?.note, "remote")
    }

    func testMessageFeedbackNoteSaveUsesCommittedRatingAndVersion() async {
        let reached = expectation(description: "feedback note seed reaches typed Host facade")
        let initial = MessageFeedbackListResponse(
            ok: true,
            value: .init(items: [
                .init(messageId: "assistant-note", rating: .positive, note: "old", version: "v1", createdAt: 1, updatedAt: 1),
            ]),
            error: nil
        )
        let feedbackAPI = RecordingMessageFeedbackAPI(response: initial, reached: reached)
        feedbackAPI.putResponse = .init(
            ok: true,
            value: .init(messageId: "assistant-note", rating: .positive, note: "new", version: "v2", createdAt: 1, updatedAt: 2),
            error: nil
        )
        let store = NativeSessionStore()
        store.open(sessionID: "feedback-note", using: RejectingSessionAPI(promptReachedFacade: nil), endpoint: URL(string: "http://127.0.0.1:1")!)
        store.setMessageFeedbackAPIForTesting(feedbackAPI)
        store.refreshMessageFeedback()
        await fulfillment(of: [reached], timeout: 1)
        await eventually(timeout: 1) { store.messageFeedbackItems["assistant-note"]?.version == "v1" }

        store.saveMessageFeedbackNote(messageID: "assistant-note", note: "  new  ")
        await eventually(timeout: 1) { feedbackAPI.putRequests.count == 1 && store.messageFeedbackItems["assistant-note"]?.version == "v2" }
        XCTAssertEqual(feedbackAPI.putRequests.first?.rating, .positive)
        XCTAssertEqual(feedbackAPI.putRequests.first?.note, "new")
        XCTAssertEqual(feedbackAPI.putRequests.first?.ifVersion, "v1")
    }

    func testPermissionProjectionAndCommandSelectionStayHostAuthoritative() async {
        let submitted = expectation(description: "permission command reaches session facade")
        let api = PermissionCommandSessionAPI(submitted: submitted)
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.projections.apply(
            sessionID: sessionID,
            key: "permissions",
            value: .object([
                "options": .array([
                    .object(["value": .string("workspace-write"), "name": .string("workspace-write"), "description": .string("Workspace access")]),
                    .object(["value": .string("danger-full-access"), "name": .string("danger-full-access"), "description": .string("Full access")]),
                    .object(["value": .string("custom"), "name": .string("Custom")]),
                ]),
                "currentValue": .string("workspace-write"),
            ]),
            seq: 12
        )
        store.setSessionAPIForTesting(api)

        XCTAssertEqual(store.extensionState?.permissions?.currentValue, "workspace-write")
        XCTAssertEqual(store.extensionState?.permissions?.options.map(\.value), ["workspace-write", "danger-full-access", "custom"])
        store.selectPermissionPreset("custom")
        XCTAssertTrue(api.prompts.isEmpty, "derived custom is current-only and must not route to the command")
        store.selectPermissionPreset("unknown")
        XCTAssertTrue(api.prompts.isEmpty, "unknown options must fail closed before command dispatch")

        store.selectPermissionPreset("danger-full-access")
        await fulfillment(of: [submitted], timeout: 1)
        await eventually(timeout: 1) { !store.isSubmittingPermission }
        XCTAssertEqual(api.prompts, [.init(sessionID: sessionID, content: [.text(text: "/permission danger-full-access")], mode: .queue)])
        XCTAssertEqual(store.extensionState?.permissions?.currentValue, "workspace-write", "only the next Host projection may confirm selection")

        store.projections.apply(sessionID: sessionID, key: "permissions", value: .object(["options": .array([]), "currentValue": .string("workspace-write")]), seq: 13)
        XCTAssertNil(store.extensionState?.permissions, "malformed Host projection must hide the optional capability")
    }

    func testModelSelectionUsesAdvertisedRouteAndHostConfirmedSelectionOnly() async {
        let modelsLoaded = expectation(description: "model directory reaches typed Host facade")
        let selectionReached = expectation(description: "model selection reaches typed Host facade")
        let api = SelectingModelSessionAPI(modelsLoaded: modelsLoaded, selectionReached: selectionReached)
        let store = NativeSessionStore()
        store.open(sessionID: "model-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await fulfillment(of: [modelsLoaded], timeout: 1)
        await eventually(timeout: 1) { store.modelDirectory?.current.model == "model-a" }
        XCTAssertEqual(store.modelDirectoryStatus, .ready)

        store.selectModel(provider: "provider-a", model: "unknown", reasoningEffort: nil)
        XCTAssertTrue(api.requests.isEmpty, "unknown catalog members must fail closed before a Host mutation")

        store.selectModel(provider: "provider-a", model: "model-b", reasoningEffort: "deep")
        await fulfillment(of: [selectionReached], timeout: 1)
        await eventually(timeout: 1) { store.modelDirectory?.current.model == "model-b" && !store.isSelectingModel }
        XCTAssertEqual(store.modelDirectoryStatus, .ready)
        XCTAssertEqual(api.requests, [.init(sessionId: "model-session", provider: "provider-a", model: "model-b", reasoningEffort: "deep")])

        api.shouldReject = true
        store.selectModel(provider: "provider-a", model: "model-a", reasoningEffort: "balanced")
        await eventually(timeout: 1) { api.requests.count == 2 && !store.isSelectingModel }
        guard case .error = store.modelDirectoryStatus else {
            return XCTFail("rejected model selection must publish the typed error lifecycle")
        }
        XCTAssertEqual(store.modelDirectory?.current.model, "model-b", "a rejected Host mutation must not optimistically replace the current selection")
    }

    func testSubagentCatalogPublishesOnlyHostCompleteSnapshotAndFailsClosed() async {
        let catalog = SubagentListResponse(entries: [
            .init(kind: "child", id: "child-a", activity: "running", hasChildren: true, mode: "continuable", label: "Investigate", reason: nil),
            .init(kind: "diagnostic", id: "bad-a", activity: nil, hasChildren: nil, mode: nil, label: nil, reason: "corrupt"),
        ], parentAvailable: true)
        let reached = expectation(description: "subagent catalog reaches typed Host facade")
        let api = RecordingSubagentCatalogAPI(catalog: catalog, reached: reached)
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.setSubagentCatalogAPIForTesting(api)

        store.refreshSubagentCatalog()
        await fulfillment(of: [reached], timeout: 1)
        await eventually(timeout: 1) { store.subagentCatalog == catalog && !store.isLoadingSubagentCatalog }
        XCTAssertEqual(api.parentIDs, ["snapshot-tooling"])
        XCTAssertEqual(store.subagentCatalog?.entries.map(\.id), ["child-a", "bad-a"])

        let retryAPI = RecordingSubagentCatalogAPI(catalog: catalog, error: DSHTransportError.invalidEndpoint)
        store.setSubagentCatalogAPIForTesting(retryAPI)
        store.refreshSubagentCatalog()
        await eventually(timeout: 1) { store.subagentCatalog == nil && !store.isLoadingSubagentCatalog }
        XCTAssertEqual(store.failedSubagentCatalogIDs, ["snapshot-tooling"])

        retryAPI.error = nil
        store.refreshSubagentCatalog()
        await eventually(timeout: 1) { store.subagentCatalog == catalog && store.failedSubagentCatalogIDs.isEmpty }
    }

    func testSubagentCatalogCachesEachExpandedParentFromHost() async {
        let rootID = "snapshot-tooling"
        let root = SubagentListResponse(entries: [
            .init(kind: "child", id: "child-parent", activity: "inactive", hasChildren: true, mode: "continuable", label: "Parent child", reason: nil),
        ], parentAvailable: true)
        let descendant = SubagentListResponse(entries: [
            .init(kind: "child", id: "grandchild", activity: "running", hasChildren: false, mode: "one-shot", label: nil, reason: nil),
        ], parentAvailable: true)
        let api = RecordingSubagentCatalogAPI(catalogs: [rootID: root, "child-parent": descendant])
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.setSubagentCatalogAPIForTesting(api)

        store.refreshSubagentCatalog()
        await eventually(timeout: 1) { store.subagentCatalogs[rootID] == root }
        store.refreshSubagentCatalog(parentSessionID: "child-parent")
        await eventually(timeout: 1) { store.subagentCatalogs["child-parent"] == descendant }

        XCTAssertEqual(api.parentIDs, [rootID, "child-parent"])
        XCTAssertNil(store.subagentCatalogs["grandchild"], "only an explicit parent refresh may create a cached branch")
    }

    func testSubagentRouteAcceptsOnlyCatalogChildWithKnownMode() {
        let store = NativeSessionStore()
        let continuable = SubagentListEntryDTO(
            kind: "child", id: "child-a", activity: "running", hasChildren: false,
            mode: "continuable", label: "Research", reason: nil
        )
        store.setSubagentRoute(parentSessionID: "parent-a", entry: continuable, parentAvailable: false)
        XCTAssertEqual(
            store.subagentRoute,
            .init(parentSessionID: "parent-a", childSessionID: "child-a", mode: .continuable, parentAvailable: false)
        )

        let diagnostic = SubagentListEntryDTO(
            kind: "diagnostic", id: "not-a-child", activity: nil, hasChildren: nil,
            mode: nil, label: nil, reason: "invalid"
        )
        store.setSubagentRoute(parentSessionID: "parent-a", entry: diagnostic, parentAvailable: true)
        XCTAssertNil(store.subagentRoute)
    }

    func testContinuableSubagentRouteUsesParentChildPromptAndInterrupt() async {
        let promptReached = expectation(description: "subagent prompt reaches continuation facade")
        let interruptReached = expectation(description: "subagent interrupt reaches continuation facade")
        let sessionAPI = RejectingSessionAPI(promptReachedFacade: nil)
        let continuationAPI = RecordingSubagentContinuationAPI(
            promptReached: promptReached,
            interruptReached: interruptReached
        )
        let store = NativeSessionStore()
        let childID = "child-continuable"
        store.open(
            sessionID: childID,
            using: sessionAPI,
            endpoint: URL(string: "http://127.0.0.1:1")!,
            subagentContinuationAPI: continuationAPI
        )
        store.setSubagentRoute(
            parentSessionID: "parent-session",
            entry: .init(kind: "child", id: childID, activity: "running", hasChildren: false, mode: "continuable", label: nil, reason: nil),
            parentAvailable: true
        )
        store.draft = "continue research"
        store.submitDraft()
        await fulfillment(of: [promptReached], timeout: 1)
        await eventually(timeout: 1) { store.draft.isEmpty }

        XCTAssertEqual(sessionAPI.prompts, [])
        XCTAssertEqual(
            continuationAPI.prompts,
            [.init(parentSessionId: "parent-session", childSessionId: childID, content: [.text(text: "continue research")], clientTimeZone: TimeZone.current.identifier)]
        )

        store.applyMuxFrame(sessionEventFrame(
            sessionID: childID, seq: 1, type: "turn/start", data: .object(["turn": .number(1)])
        ), sessionID: childID)
        store.cancelRunningTurn()
        await fulfillment(of: [interruptReached], timeout: 1)

        XCTAssertEqual(sessionAPI.cancelledSessionIDs, [])
        XCTAssertEqual(continuationAPI.interrupts, [.init(parentSessionId: "parent-session", childSessionId: childID)])
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

    func testSubscriptionWatermarkAheadOfHistoryTailRecoversAuthorityWindow() async {
        let recoveryReachedHistory = expectation(description: "ahead subscription watermark triggers authority history")
        let api = GapRecoveringSessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "ahead-subscription", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string("recovery-session"),
            "lastSeq": .number(2),
        ])), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline", "recovered authority"] }

        XCTAssertEqual(store.items.map(\.sequence), [1, 2])
        XCTAssertEqual(store.modelDirectory?.current.model, "model-recovered")
        XCTAssertEqual(store.modelDirectoryStatus, .ready)
    }

    func testSubscriptionWatermarkRecoveryRebuildsProjectionBaselineFromHostAuthority() async {
        let recoveryReachedHistory = expectation(description: "watermark rollback refreshes history projections")
        let api = GapRecoveringSessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) {
            store.projections.value(sessionID: "recovery-session", key: "obsolete-host-value") == .string("initial baseline")
        }

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "restart-projections", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string("recovery-session"),
            "lastSeq": .number(0),
        ])), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)
        await eventually(timeout: 1) {
            store.projections.value(sessionID: "recovery-session", key: "latest-host-value") == .string("recovered baseline")
        }

        XCTAssertNil(store.projections.value(sessionID: "recovery-session", key: "obsolete-host-value"))
        XCTAssertEqual(store.projections.row(sessionID: "recovery-session", key: "latest-host-value")?.seq, 2)
    }

    func testGapRecoveryReplacesWholeProjectionBaselineFromLatestHostAuthority() async {
        let recoveryReachedHistory = expectation(description: "gap refreshes history projection baseline")
        let api = GapRecoveringSessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) {
            store.projections.value(sessionID: "recovery-session", key: "obsolete-host-value") == .string("initial baseline")
        }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("gap-projections"),
                "content": .array([.object(["type": .string("text"), "text": .string("must not append")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)
        await eventually(timeout: 1) {
            store.projections.value(sessionID: "recovery-session", key: "latest-host-value") == .string("recovered baseline")
        }

        XCTAssertNil(store.projections.value(sessionID: "recovery-session", key: "obsolete-host-value"))
        XCTAssertEqual(store.projections.row(sessionID: "recovery-session", key: "latest-host-value")?.seq, 2)
    }

    func testGapRecoveryRebuildsModelDirectoryFromLatestHostBaseline() async {
        let recoveryReachedHistory = expectation(description: "gap refreshes model directory with authority history")
        let api = GapRecoveringSessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.modelDirectory?.current.model == "model" }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("gap-models"),
                "content": .array([.object(["type": .string("text"), "text": .string("must not append")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)
        await eventually(timeout: 1) { store.modelDirectory?.current.model == "model-recovered" }

        XCTAssertEqual(store.modelDirectoryStatus, .ready)
        XCTAssertEqual(store.modelDirectory?.current.provider, "provider-recovered")
    }

    func testGapRecoveryCancelsStaleModelSelectionAndClearsBusyState() async {
        let selectionReached = expectation(description: "old selection reaches non-cooperative Host facade")
        let recoveryReachedModels = expectation(description: "gap recovery reads a new model baseline")
        let api = RecoveringSelectionSessionAPI(
            selectionReached: selectionReached,
            recoveryReachedModels: recoveryReachedModels
        )
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-selection", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.modelDirectory?.current.model == "model-a" }

        store.selectModel(provider: "provider-a", model: "model-b", reasoningEffort: "deep")
        await fulfillment(of: [selectionReached], timeout: 1)
        XCTAssertTrue(store.isSelectingModel)

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-selection",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("gap-selection"),
                "content": .array([.object(["type": .string("text"), "text": .string("must not append")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-selection")
        await fulfillment(of: [recoveryReachedModels], timeout: 1)
        await eventually(timeout: 1) {
            !store.isSelectingModel && store.modelDirectory?.current.model == "model-recovered"
        }

        await api.releaseSelection()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.modelDirectory?.current.model, "model-recovered")
        XCTAssertEqual(store.modelDirectoryStatus, .ready)
    }

    func testGapRecoveryDoesNotRegressNewerLiveProjectionWithHistoryBaseline() async {
        let recoveryReachedHistory = expectation(description: "gap recovery history remains gated for projection frame")
        let api = StitchingGapRecoverySessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("gap-for-projection"),
                "content": .array([.object(["type": .string("text"), "text": .string("buffered gap")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "newer-projection", method: "session/projection", payload: .object([
            "type": .string("session/projection"),
            "sessionId": .string("recovery-session"),
            "key": .string("recovery-projection"),
            "value": .string("live push wins"),
            "seq": .number(3),
        ])), sessionID: "recovery-session")
        await api.releaseRecoveryHistory()
        await eventually(timeout: 1) {
            store.projections.value(sessionID: "recovery-session", key: "recovery-projection") == .string("live push wins")
        }

        XCTAssertEqual(store.projections.row(sessionID: "recovery-session", key: "recovery-projection")?.seq, 3)
        XCTAssertEqual(store.items.map(\.sequence), [1, 2, 3])
    }

    func testHostRestartRecoverySupersedesStaleGapRepairWithoutDroppingLiveBuffer() async {
        let staleHistoryReached = expectation(description: "initial gap repair history is delayed")
        let newHistoryReached = expectation(description: "Host restart issues newer recovery history")
        let api = SupersedingGapRecoverySessionAPI(
            staleHistoryReached: staleHistoryReached,
            newHistoryReached: newHistoryReached
        )
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("surviving-live-tail"),
                "content": .array([.object(["type": .string("text"), "text": .string("surviving live tail")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [staleHistoryReached], timeout: 1)

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "host-restart", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string("recovery-session"),
            "lastSeq": .number(0),
        ])), sessionID: "recovery-session")
        await fulfillment(of: [newHistoryReached], timeout: 1)
        await api.releaseStaleHistory()
        await eventually(timeout: 1) {
            store.items.map(\.text) == ["baseline", "new host authority", "surviving live tail"]
        }

        XCTAssertEqual(store.items.map(\.sequence), [1, 2, 3])
        XCTAssertFalse(store.items.contains(where: { $0.text == "stale authority" }))
        XCTAssertEqual(store.modelDirectory?.current.model, "model-new")
        XCTAssertEqual(store.modelDirectoryStatus, .ready)
    }

    func testFailedGapRecoveryKeepsBufferedFramesForLaterSuccessfulRepair() async {
        let failedHistory = expectation(description: "first gap history repair fails")
        let successfulHistory = expectation(description: "second gap history repair succeeds")
        let api = FailThenStitchGapRecoverySessionAPI(
            failedHistory: failedHistory,
            successfulHistory: successfulHistory
        )
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("failed-gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("retained after failure")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [failedHistory], timeout: 1)
        await eventually(timeout: 1) {
            if case .error = store.modelDirectoryStatus { return true }
            return false
        }
        XCTAssertEqual(store.items.map(\.text), ["baseline"])

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 4,
            type: "user/message",
            data: .object([
                "id": .string("later-gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("later recovered tail")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [successfulHistory], timeout: 1)
        await eventually(timeout: 1) {
            store.items.map(\.text) == ["baseline", "recovered authority", "retained after failure", "later recovered tail"]
        }

        XCTAssertEqual(store.items.map(\.sequence), [1, 2, 3, 4])
        XCTAssertEqual(store.modelDirectoryStatus, .ready)
    }

    func testGapRecoveryStitchesBufferedLiveEventsAfterLatestHostWindow() async {
        let recoveryReachedHistory = expectation(description: "gap recovery starts delayed authority history")
        let api = StitchingGapRecoverySessionAPI(recoveryReachedHistory: recoveryReachedHistory)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("buffered-gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("buffered gap")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)

        // RC8 stitches from the recovered Host cut: a buffered overlap at the
        // cut loses by sequence, while frames strictly after it remain live.
        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 2,
            type: "user/message",
            data: .object([
                "id": .string("overlap"),
                "content": .array([.object(["type": .string("text"), "text": .string("must not replace authority")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        store.applyMuxFrame(sessionEventFrame(
            sessionID: "recovery-session",
            seq: 4,
            type: "user/message",
            data: .object([
                "id": .string("buffered-tail"),
                "content": .array([.object(["type": .string("text"), "text": .string("buffered tail")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await api.releaseRecoveryHistory()
        await eventually(timeout: 1) {
            store.items.map(\.text) == ["baseline", "recovered authority", "buffered gap", "buffered tail"]
        }

        XCTAssertEqual(store.items.map(\.sequence), [1, 2, 3, 4])
        XCTAssertFalse(store.items.contains(where: { $0.text == "must not replace authority" }))
        XCTAssertEqual(store.chatNodes.compactMap { $0.data as? CoreUserMessageNode }.map(\.seq), [1, 2, 3, 4])
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

    func testToolingFixtureMaterializesTrajectoryTargetSeparatelyFromChat() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()

        XCTAssertEqual(store.chatNodes.map(\.target), ["chat", "chat"])
        XCTAssertEqual(store.trajectoryNodes.map(\.target), ["trajectory"])
        XCTAssertEqual(store.trajectoryNodes.map(\.kind), ["trajectory-input-message"])
        XCTAssertEqual((store.trajectoryNodes.first?.data as? CoreUserMessageNode)?.content.compactMap(\.text).joined(), "Read the project instructions.")
    }

    func testSnapshotQueueFixtureUsesOnlyQueuedHostRows() {
        let store = NativeSessionStore()
        store.loadSnapshotQueueFixture()

        XCTAssertEqual(store.selectedSessionID, "snapshot-tooling")
        XCTAssertTrue(store.isRunning)
        XCTAssertNil(store.selectedToolCallID)
        XCTAssertEqual(store.queuedMessages.map(\.id), ["snapshot-queue-text", "snapshot-queue-image"])
        XCTAssertTrue(store.queuedMessages.allSatisfy { $0.placement == .queued })
        XCTAssertEqual(store.queuedMessages.first?.text, "Update the native screenshot baseline")
        XCTAssertNil(store.queuedMessages.last?.text)
    }

    func testSnapshotGoalFixtureUsesCurrentHostGoalProjection() {
        let store = NativeSessionStore()
        store.loadSnapshotGoalFixture()

        XCTAssertEqual(store.selectedSessionID, "snapshot-tooling")
        XCTAssertFalse(store.isRunning)
        XCTAssertNil(store.selectedToolCallID)
        XCTAssertEqual(store.extensionState?.goal?.id, "snapshot-goal")
        XCTAssertEqual(store.extensionState?.goal?.objective, "Rebuild the official client as a native macOS app")
        XCTAssertEqual(store.extensionState?.goal?.phase, .active)
    }

    func testGoalActionsUseActiveHostProjectionRefWithoutOptimisticMutation() async {
        let store = NativeSessionStore()
        store.loadSnapshotTodoFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.projections.apply(sessionID: sessionID, key: "goal", value: goalProjection(id: "goal-1", revision: 4, objective: "Ship safely", phase: "active"), seq: 106)
        let invoked = expectation(description: "pause goal reaches typed Host seam")
        let api = RecordingGoalAPI(invoked: invoked)
        store.setGoalAPIForTesting(api)

        store.pauseGoal()
        await fulfillment(of: [invoked], timeout: 1)
        await eventually(timeout: 1) { !store.isSubmittingGoal }

        XCTAssertEqual(api.pauseRequests, [.init(sessionId: sessionID, ref: .init(id: "goal-1", revision: 4))])
        XCTAssertFalse(store.isSubmittingGoal)
        XCTAssertNil(store.goalActionFailure)
        XCTAssertNil(store.locallyClearedGoalID)
        XCTAssertEqual(store.extensionState?.goal?.objective, "Ship safely", "successful RPC waits for the authoritative goal projection rather than locally changing state")
        XCTAssertEqual(store.extensionState?.goal?.phase, .active)
    }

    func testSuccessfulGoalClearUsesPresentationMarkerWithoutMutatingProjection() async {
        let store = NativeSessionStore()
        store.loadSnapshotTodoFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.projections.apply(sessionID: sessionID, key: "goal", value: goalProjection(id: "goal-clear", revision: 6, objective: "Clear from bar", phase: "active"), seq: 106)
        let invoked = expectation(description: "clear goal reaches typed Host seam")
        let api = RecordingGoalAPI(invoked: invoked)
        store.setGoalAPIForTesting(api)

        store.clearGoal()
        await fulfillment(of: [invoked], timeout: 1)
        await eventually(timeout: 1) { !store.isSubmittingGoal }

        XCTAssertEqual(api.clearRequests, [.init(sessionId: sessionID, ref: .init(id: "goal-clear", revision: 6))])
        XCTAssertEqual(store.locallyClearedGoalID, "goal-clear")
        XCTAssertEqual(store.extensionState?.goal?.objective, "Clear from bar", "the core never replaces Host projection data with a local tombstone")
    }

    func testGoalActionSurfacesOnlyHostBusinessFailureAndKeepsProjection() async {
        let store = NativeSessionStore()
        store.loadSnapshotTodoFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.projections.apply(sessionID: sessionID, key: "goal", value: goalProjection(id: "goal-2", revision: 7, objective: "Keep scope", phase: "active"), seq: 106)
        let invoked = expectation(description: "clear goal reaches typed Host seam")
        let api = RecordingGoalAPI(invoked: invoked, error: .init(code: "revision_conflict", message: "refresh goal", details: .object([:])))
        store.setGoalAPIForTesting(api)

        store.clearGoal()
        await fulfillment(of: [invoked], timeout: 1)
        await eventually(timeout: 1) { !store.isSubmittingGoal }

        XCTAssertEqual(api.clearRequests, [.init(sessionId: sessionID, ref: .init(id: "goal-2", revision: 7))])
        XCTAssertFalse(store.isSubmittingGoal)
        XCTAssertEqual(store.goalActionFailure, .init(message: "refresh goal", code: "revision_conflict"))
        XCTAssertNil(store.locallyClearedGoalID)
        XCTAssertEqual(store.extensionState?.goal?.objective, "Keep scope")
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

    func testQueueActionUsesActiveHostItemAndWaitsForWholeSnapshot() async {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-edit", messageID: "m-edit", placement: "queued", content: [.object(["type": .string("text"), "text": .string("original")])]),
        ]), sessionID: sessionID)
        let invoked = expectation(description: "queue edit reaches typed session facade")
        let api = RecordingQueueSessionAPI(invoked: invoked)
        store.setSessionAPIForTesting(api)

        store.updateQueuedMessage(itemID: "q-edit", action: .edit(content: [.text(text: "edited")]))
        await fulfillment(of: [invoked], timeout: 1)
        await eventually(timeout: 1) { store.updatingQueueItemID == nil }

        XCTAssertEqual(api.requests, [.init(sessionId: sessionID, itemId: "q-edit", action: .edit(content: [.text(text: "edited")]))])
        XCTAssertNil(store.queueActionFailure)
        XCTAssertEqual(store.queuedMessages.map(\.preview), ["original"], "queue content remains Host-owned until session/queue sends a replacement snapshot")
    }

    func testQueueActionFailureIsScopedToTheActionAndDoesNotRetireRow() async {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-remove", messageID: "m-remove", placement: "queued", content: [.object(["type": .string("text"), "text": .string("retain until host frame")])]),
        ]), sessionID: sessionID)
        let invoked = expectation(description: "queue remove reaches typed session facade")
        let api = RecordingQueueSessionAPI(invoked: invoked, error: DSHTransportError.invalidEndpoint)
        store.setSessionAPIForTesting(api)

        store.updateQueuedMessage(itemID: "q-remove", action: .remove)
        await fulfillment(of: [invoked], timeout: 1)
        await eventually(timeout: 1) { store.updatingQueueItemID == nil }

        XCTAssertEqual(store.queueActionFailure, .init(itemID: "q-remove", kind: .remove))
        XCTAssertEqual(store.queuedMessages.map(\.id), ["q-remove"])
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
        let expectedChatNodeKeys = store.chatNodes.map(\.key)
        let expectedChatNodeKinds = store.chatNodes.map(\.kind)
        let expectedTrajectoryNodeKeys = store.trajectoryNodes.map(\.key)
        let expectedTrajectoryNodeKinds = store.trajectoryNodes.map(\.kind)
        store.applyMuxFrame(queueFrame(sessionID: "snapshot-tooling", items: [
            queuedItem(id: "q-1", messageID: "m-1", placement: "steering", content: [.object(["type": .string("text"), "text": .string("retain me")])]),
        ]), sessionID: "snapshot-tooling")
        store.applyMuxFrame(jobsFrame(sessionID: "snapshot-tooling", jobs: [job(id: "job-1", status: "stopping", startedAt: 1)]), sessionID: "snapshot-tooling")
        store.preserveActiveState()

        store.loadSnapshotQuestionFixture()
        XCTAssertTrue(store.restoreResidentState(for: "snapshot-tooling"))

        XCTAssertEqual(store.items.map(\.id), ["event-101", "event-104"])
        XCTAssertEqual(store.chatNodes.map(\.key), expectedChatNodeKeys)
        XCTAssertEqual(store.chatNodes.map(\.kind), expectedChatNodeKinds)
        XCTAssertEqual(store.trajectoryNodes.map(\.key), expectedTrajectoryNodeKeys)
        XCTAssertEqual(store.trajectoryNodes.map(\.kind), expectedTrajectoryNodeKinds)
        XCTAssertEqual(store.trajectoryNodes.map(\.target), ["trajectory"])
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

    func testSnapshotFeedbackFixtureSettlesTypedAssistantAndPublishesSidecar() {
        let store = NativeSessionStore()
        store.loadSnapshotFeedbackFixture()

        let assistant = tryUnwrap(store.chatNodes.compactMap { $0.data as? CoreAssistantNode }.first)
        XCTAssertEqual(assistant.messageID, "event-104")
        XCTAssertEqual(assistant.status, .settled)
        XCTAssertEqual(store.messageFeedbackItems["event-104"]?.rating, .positive)
        XCTAssertEqual(store.messageFeedbackItems["event-104"]?.note, "Useful implementation summary.")
        XCTAssertTrue(store.isMessageFeedbackAvailable)
        XCTAssertFalse(store.isRunning)
    }

    func testSnapshotRetryFixtureMaterializesScheduledTypedAttempt() {
        let store = NativeSessionStore()
        store.loadSnapshotRetryFixture()

        let retry = tryUnwrap(store.chatNodes.first(where: { $0.kind == "model-retry" })?.data as? CoreRetryNode)
        XCTAssertEqual(retry.attempts, [
            .init(
                seq: 105,
                time: 105,
                retry: 1,
                state: .scheduled,
                delayMilliseconds: 1_250,
                failureMessage: "provider busy",
                maximumRetries: 3,
                unlimited: false
            ),
        ])
        XCTAssertTrue(store.isRunning)
    }

    func testSnapshotCompactionFixtureMaterializesLandedTypedCheckpoint() {
        let store = NativeSessionStore()
        store.loadSnapshotCompactionFixture()

        let compaction = tryUnwrap(store.chatNodes.first(where: { $0.kind == "compaction" })?.data as? CoreCompactionNode)
        XCTAssertEqual(compaction.compactionID, "snapshot-compact")
        XCTAssertEqual(compaction.summary, "The earlier workspace review and source inspection were condensed into this checkpoint.")
        XCTAssertEqual(compaction.shadowedItemCount, 3)
        XCTAssertEqual(compaction.shadowedTokenCount, 99)
        XCTAssertEqual(compaction.seq, 106)
        XCTAssertFalse(store.isRunning)
    }

    func testSnapshotPermissionFixturePublishesWholeHostProjection() {
        let store = NativeSessionStore()
        store.loadSnapshotPermissionFixture()

        XCTAssertEqual(store.selectedSessionID, "fx-alpha")
        XCTAssertEqual(store.extensionState?.permissions?.currentValue, "workspace-write")
        XCTAssertEqual(store.extensionState?.permissions?.options.map(\.value), ["workspace-write", "danger-full-access"])
        XCTAssertEqual(store.extensionState?.permissions?.options.map(\.name), ["workspace-write", "danger-full-access"])
        XCTAssertFalse(store.isSubmittingPermission)
        XCTAssertFalse(store.isRunning)
    }

    func testSnapshotModelSelectionFixturePublishesCompleteHostDirectory() {
        let store = NativeSessionStore()
        store.loadSnapshotModelSelectionFixture()

        XCTAssertEqual(store.selectedSessionID, "fx-alpha")
        XCTAssertEqual(store.modelDirectory?.current.provider, "deepseek-official")
        XCTAssertEqual(store.modelDirectory?.current.model, "deepseek-v4")
        XCTAssertEqual(store.modelDirectory?.current.reasoningEffort, "balanced")
        XCTAssertTrue(store.modelDirectory?.routable == true)
        XCTAssertEqual(store.modelDirectory?.groups.map(\.id), ["deepseek-official", "local"])
        XCTAssertEqual(store.modelDirectory?.groups.first?.models.map(\.id), ["deepseek-v4", "deepseek-v4-fast"])
        XCTAssertEqual(store.modelDirectory?.groups.first?.models.first?.reasoningEfforts.map(\.id), ["balanced", "deep"])
        XCTAssertEqual(store.modelDirectory?.failures.map(\.id), ["fixture-unavailable"])
        XCTAssertFalse(store.isSelectingModel)
        XCTAssertFalse(store.isRunning)
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

    private func goalProjection(id: String, revision: Int, objective: String, phase: String) -> JSONValue {
        .object([
            "goal": .object([
                "id": .string(id),
                "revision": .number(Double(revision)),
                "objective": .string(objective),
                "phase": .string(phase),
                "maxGoalRounds": .number(4),
            ]),
            "roundsStarted": .number(0),
            "createdAt": .number(100),
            "updatedAt": .number(100),
        ])
    }

    @MainActor
    private final class RecordingGoalAPI: NativeGoalAPI {
        let invoked: XCTestExpectation
        let error: RPCBusinessError?
        private(set) var editRequests: [GoalEditRequest] = []
        private(set) var pauseRequests: [GoalReferenceRequest] = []
        private(set) var resumeRequests: [GoalReferenceRequest] = []
        private(set) var clearRequests: [GoalReferenceRequest] = []

        init(invoked: XCTestExpectation, error: RPCBusinessError? = nil) {
            self.invoked = invoked
            self.error = error
        }

        func edit(_ request: GoalEditRequest) async throws -> GoalReferenceResponse {
            editRequests.append(request)
            invoked.fulfill()
            if let error { throw error }
            return .init(ref: request.ref)
        }

        func pause(_ request: GoalReferenceRequest) async throws -> GoalReferenceResponse {
            pauseRequests.append(request)
            invoked.fulfill()
            if let error { throw error }
            return .init(ref: request.ref)
        }

        func resume(_ request: GoalReferenceRequest) async throws -> GoalReferenceResponse {
            resumeRequests.append(request)
            invoked.fulfill()
            if let error { throw error }
            return .init(ref: request.ref)
        }

        func clear(_ request: GoalReferenceRequest) async throws -> GoalClearResponse {
            clearRequests.append(request)
            invoked.fulfill()
            if let error { throw error }
            return .init(cleared: true)
        }
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
    private final class RecordingMessageFeedbackAPI: NativeMessageFeedbackAPI {
        var response: MessageFeedbackListResponse
        var reached: XCTestExpectation
        private(set) var sessionIDs: [String] = []
        private(set) var putRequests: [MessageFeedbackPutRequest] = []
        private(set) var deleteRequests: [MessageFeedbackDeleteRequest] = []
        var putResponse = MessageFeedbackPutResponse(ok: false, value: nil, error: .init(code: "target-not-found", sessionId: nil, messageId: nil, current: nil, maxBytes: nil, actualBytes: nil))
        var deleteResponse = MessageFeedbackDeleteResponse(ok: true, value: .init(absent: true), error: nil)

        init(response: MessageFeedbackListResponse, reached: XCTestExpectation) {
            self.response = response
            self.reached = reached
        }

        func list(sessionID: String) async throws -> MessageFeedbackListResponse {
            sessionIDs.append(sessionID)
            reached.fulfill()
            return response
        }

        func put(_ request: MessageFeedbackPutRequest) async throws -> MessageFeedbackPutResponse {
            putRequests.append(request)
            return putResponse
        }

        func delete(_ request: MessageFeedbackDeleteRequest) async throws -> MessageFeedbackDeleteResponse {
            deleteRequests.append(request)
            return deleteResponse
        }
    }

    @MainActor
    private final class GatedRecoveryFeedbackAPI: NativeMessageFeedbackAPI {
        var listResponse: MessageFeedbackListResponse
        let listReached: XCTestExpectation
        let mutationReached: XCTestExpectation
        private let mutationGate = RecoveryGate()
        private(set) var sessionIDs: [String] = []
        private(set) var putRequests: [MessageFeedbackPutRequest] = []

        init(
            listResponse: MessageFeedbackListResponse,
            listReached: XCTestExpectation,
            mutationReached: XCTestExpectation
        ) {
            self.listResponse = listResponse
            self.listReached = listReached
            self.mutationReached = mutationReached
        }

        func list(sessionID: String) async throws -> MessageFeedbackListResponse {
            sessionIDs.append(sessionID)
            listReached.fulfill()
            return listResponse
        }

        func put(_ request: MessageFeedbackPutRequest) async throws -> MessageFeedbackPutResponse {
            putRequests.append(request)
            mutationReached.fulfill()
            await mutationGate.wait()
            return .init(
                ok: true,
                value: .init(messageId: request.messageId, rating: request.rating, note: request.note, version: "v2", createdAt: 1, updatedAt: 2),
                error: nil
            )
        }

        func delete(_: MessageFeedbackDeleteRequest) async throws -> MessageFeedbackDeleteResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func releaseMutation() async { await mutationGate.open() }
    }

    private final class RecordingSubagentContinuationAPI: NativeSubagentContinuationAPI {
        let promptReached: XCTestExpectation
        let interruptReached: XCTestExpectation
        private(set) var prompts: [SubagentPromptRequest] = []
        private(set) var interrupts: [SubagentInterruptRequest] = []

        init(promptReached: XCTestExpectation, interruptReached: XCTestExpectation) {
            self.promptReached = promptReached
            self.interruptReached = interruptReached
        }

        func prompt(_ request: SubagentPromptRequest) async throws -> SubagentPromptResponse {
            prompts.append(request)
            promptReached.fulfill()
            return .init(messageId: "accepted")
        }

        func interrupt(_ request: SubagentInterruptRequest) async throws -> SubagentInterruptResponse {
            interrupts.append(request)
            interruptReached.fulfill()
            return .init(accepted: true)
        }
    }

    @MainActor
    private final class RecordingSubagentCatalogAPI: NativeSubagentCatalogAPI {
        let catalog: SubagentListResponse?
        let catalogs: [String: SubagentListResponse]
        var error: Error?
        let reached: XCTestExpectation?
        private(set) var parentIDs: [String] = []

        init(catalog: SubagentListResponse? = nil, catalogs: [String: SubagentListResponse] = [:], error: Error? = nil, reached: XCTestExpectation? = nil) {
            self.catalog = catalog
            self.catalogs = catalogs
            self.error = error
            self.reached = reached
        }

        func list(parentSessionID: String) async throws -> SubagentListResponse {
            parentIDs.append(parentSessionID)
            reached?.fulfill()
            if let error { throw error }
            if let catalog = catalogs[parentSessionID] { return catalog }
            guard let catalog else { throw DSHTransportError.invalidEndpoint }
            return catalog
        }
    }

    @MainActor
    private final class RecordingQueueSessionAPI: NativeSessionAPI {
        let invoked: XCTestExpectation
        let error: Error?
        private(set) var requests: [SessionUpdateQueueRequest] = []

        init(invoked: XCTestExpectation, error: Error? = nil) {
            self.invoked = invoked
            self.error = error
        }

        func updateQueue(_ request: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            requests.append(request)
            invoked.fulfill()
            if let error { throw error }
            return .init(accepted: true)
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse { throw DSHTransportError.invalidEndpoint }
        func models(sessionID _: String) async throws -> SessionModelsResponse { throw DSHTransportError.invalidEndpoint }
        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
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
    private final class SupersedingGapRecoverySessionAPI: NativeSessionAPI {
        let staleHistoryReached: XCTestExpectation
        let newHistoryReached: XCTestExpectation
        private let staleHistoryGate = RecoveryGate()
        private var historyCount = 0
        private var modelsCount = 0

        init(staleHistoryReached: XCTestExpectation, newHistoryReached: XCTestExpectation) {
            self.staleHistoryReached = staleHistoryReached
            self.newHistoryReached = newHistoryReached
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCount += 1
            let first = historyEntry(seq: 1, id: "baseline", text: "baseline")
            switch historyCount {
            case 1:
                return .init(events: [first], hasMore: false, projections: nil)
            case 2:
                staleHistoryReached.fulfill()
                await staleHistoryGate.wait()
                return .init(
                    events: [first, historyEntry(seq: 2, id: "stale", text: "stale authority")],
                    hasMore: false,
                    projections: nil
                )
            default:
                newHistoryReached.fulfill()
                return .init(
                    events: [first, historyEntry(seq: 2, id: "new", text: "new host authority")],
                    hasMore: false,
                    projections: nil
                )
            }
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsCount += 1
            let isNew = modelsCount > 2
            return .init(
                current: .init(provider: "provider", model: isNew ? "model-new" : "model-old", reasoningEffort: nil),
                routable: true,
                groups: [],
                failures: []
            )
        }

        func releaseStaleHistory() async { await staleHistoryGate.open() }
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
    private final class FailThenStitchGapRecoverySessionAPI: NativeSessionAPI {
        let failedHistory: XCTestExpectation
        let successfulHistory: XCTestExpectation
        private var historyCount = 0

        init(failedHistory: XCTestExpectation, successfulHistory: XCTestExpectation) {
            self.failedHistory = failedHistory
            self.successfulHistory = successfulHistory
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCount += 1
            let first = historyEntry(seq: 1, id: "baseline", text: "baseline")
            switch historyCount {
            case 1:
                return .init(events: [first], hasMore: false, projections: nil)
            case 2:
                failedHistory.fulfill()
                throw DSHTransportError.invalidEndpoint
            default:
                successfulHistory.fulfill()
                return .init(
                    events: [first, historyEntry(seq: 2, id: "recovered", text: "recovered authority")],
                    hasMore: false,
                    projections: nil
                )
            }
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
    private final class StitchingGapRecoverySessionAPI: NativeSessionAPI {
        let recoveryReachedHistory: XCTestExpectation
        private let historyGate = RecoveryGate()
        private var historyCount = 0

        init(recoveryReachedHistory: XCTestExpectation) {
            self.recoveryReachedHistory = recoveryReachedHistory
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCount += 1
            let first = historyEntry(seq: 1, id: "baseline", text: "baseline")
            if historyCount == 1 {
                return .init(events: [first], hasMore: false, projections: nil)
            }
            recoveryReachedHistory.fulfill()
            await historyGate.wait()
            return .init(
                events: [first, historyEntry(seq: 2, id: "recovered", text: "recovered authority")],
                hasMore: false,
                projections: .init(asOfSeq: 2, values: [
                    "recovery-projection": .string("history baseline"),
                ])
            )
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func releaseRecoveryHistory() async { await historyGate.open() }
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
    private final class GapRecoveringSessionAPI: NativeSessionAPI {
        let recoveryReachedHistory: XCTestExpectation
        private var historyCount = 0
        private var modelsCount = 0

        init(recoveryReachedHistory: XCTestExpectation) {
            self.recoveryReachedHistory = recoveryReachedHistory
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCount += 1
            if historyCount > 1 { recoveryReachedHistory.fulfill() }
            let first = historyEntry(seq: 1, id: "baseline", text: "baseline")
            if historyCount == 1 {
                return .init(
                    events: [first],
                    hasMore: false,
                    projections: .init(asOfSeq: 1, values: [
                        "obsolete-host-value": .string("initial baseline"),
                    ])
                )
            }
            return .init(
                events: [first, historyEntry(seq: 2, id: "recovered", text: "recovered authority")],
                hasMore: false,
                projections: .init(asOfSeq: 2, values: [
                    "latest-host-value": .string("recovered baseline"),
                ])
            )
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsCount += 1
            if modelsCount == 1 {
                return .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
            }
            return .init(current: .init(provider: "provider-recovered", model: "model-recovered", reasoningEffort: nil), routable: true, groups: [], failures: [])
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
    private final class PermissionCommandSessionAPI: NativeSessionAPI {
        struct Prompt: Equatable {
            let sessionID: String
            let content: [SessionPromptContent]
            let mode: SessionPromptMode
        }

        let submitted: XCTestExpectation
        private(set) var prompts: [Prompt] = []

        init(submitted: XCTestExpectation) {
            self.submitted = submitted
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse { throw DSHTransportError.invalidEndpoint }
        func models(sessionID _: String) async throws -> SessionModelsResponse { throw DSHTransportError.invalidEndpoint }
        func prompt(sessionID: String, content: [SessionPromptContent], mode: SessionPromptMode) async throws -> SessionPromptResponse {
            prompts.append(.init(sessionID: sessionID, content: content, mode: mode))
            submitted.fulfill()
            return .init(accepted: true)
        }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class RecoveringSelectionSessionAPI: NativeSessionAPI {
        let selectionReached: XCTestExpectation
        let recoveryReachedModels: XCTestExpectation
        private let selectionGate = RecoveryGate()
        private var modelsCount = 0

        init(selectionReached: XCTestExpectation, recoveryReachedModels: XCTestExpectation) {
            self.selectionReached = selectionReached
            self.recoveryReachedModels = recoveryReachedModels
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [.init(event: .init(
                type: "user/message", seq: 1, time: 1,
                data: .object([
                    "id": .string("baseline"),
                    "content": .array([.object(["type": .string("text"), "text": .string("baseline")])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: .string("append"), sourceEventSeqs: nil, ignorable: nil
            ), view: nil)], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsCount += 1
            if modelsCount > 1 { recoveryReachedModels.fulfill() }
            let recovered = modelsCount > 1
            return .init(
                current: .init(
                    provider: recovered ? "provider-recovered" : "provider-a",
                    model: recovered ? "model-recovered" : "model-a",
                    reasoningEffort: recovered ? nil : "balanced"
                ),
                routable: true,
                groups: [.init(id: "provider-a", name: "Provider A", models: [
                    .init(id: "model-a", name: "Model A", description: nil, reasoning: .init(
                        efforts: [.init(id: "balanced", name: "Balanced", description: nil)], defaultEffort: "balanced"
                    )),
                    .init(id: "model-b", name: "Model B", description: nil, reasoning: .init(
                        efforts: [.init(id: "deep", name: "Deep", description: nil)], defaultEffort: "deep"
                    )),
                ])],
                failures: []
            )
        }

        func selectModel(_ request: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            selectionReached.fulfill()
            await selectionGate.wait()
            return .init(selected: .init(provider: request.provider, model: request.model, reasoningEffort: request.reasoningEffort))
        }

        func releaseSelection() async { await selectionGate.open() }
        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class SelectingModelSessionAPI: NativeSessionAPI {
        let modelsLoaded: XCTestExpectation
        let selectionReached: XCTestExpectation
        var shouldReject = false
        private(set) var requests: [SessionSelectModelRequest] = []

        init(modelsLoaded: XCTestExpectation, selectionReached: XCTestExpectation) {
            self.modelsLoaded = modelsLoaded
            self.selectionReached = selectionReached
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
                    .init(id: "model-a", name: "Model A", description: nil, reasoning: .init(
                        efforts: [.init(id: "balanced", name: "Balanced", description: nil)],
                        defaultEffort: "balanced"
                    )),
                    .init(id: "model-b", name: "Model B", description: nil, reasoning: .init(
                        efforts: [.init(id: "deep", name: "Deep", description: nil)],
                        defaultEffort: "deep"
                    )),
                ])],
                failures: []
            )
        }

        func selectModel(_ request: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            requests.append(request)
            if requests.count == 1 { selectionReached.fulfill() }
            if shouldReject { throw DSHTransportError.invalidEndpoint }
            return .init(selected: .init(provider: request.provider, model: request.model, reasoningEffort: request.reasoningEffort))
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class RejectingSessionAPI: NativeSessionAPI {
        struct Prompt: Equatable {
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
