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

    func testRejectedAdmittedImagePromptRetainsDraftAndAttachmentForRetry() async throws {
        let promptReachedFacade = expectation(description: "rejected typed facade receives admitted image content")
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9UQAAAABJRU5ErkJggg==")!
        let api = RejectingSessionAPI(
            promptReachedFacade: promptReachedFacade,
            opensAuthority: true,
            imageLimits: .init(
                maxImageBytes: 4_096,
                maxImagesPerMessage: 2,
                maxMessageImageBytes: 8_192,
                maxImagePixels: 16,
                maxImageDimension: 4,
                mediaTypes: ["image/png"]
            )
        )
        let store = NativeSessionStore()
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rejected-native-session-image-\(UUID().uuidString).png")
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        store.open(sessionID: "rejected-image-prompt-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.imageAttachmentLimits != nil }
        store.draft = "keep this retryable"
        store.addPendingImage(imageURL)
        store.submitDraft()
        await fulfillment(of: [promptReachedFacade], timeout: 1)
        await eventually(timeout: 1) { !store.isSubmittingPrompt }

        XCTAssertEqual(api.prompts.first?.content, [
            .text(text: "keep this retryable"),
            .image(mediaType: "image/png", data: imageData.base64EncodedString(), name: imageURL.lastPathComponent),
        ])
        XCTAssertEqual(store.draft, "keep this retryable")
        XCTAssertEqual(store.pendingImages.count, 1)
        XCTAssertEqual(store.pendingImages.first?.name, imageURL.lastPathComponent)
    }

    func testCancelIntentUsesTypedFacadeOnlyForHostRunningTurn() async {
        let cancelReachedFacade = expectation(description: "typed cancel facade receives running turn intent")
        let api = RejectingSessionAPI(promptReachedFacade: nil, cancelReachedFacade: cancelReachedFacade, opensAuthority: true)
        let store = NativeSessionStore()
        let sessionID = "cancel-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }

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

    func testFailedOpenDropsLiveEventsUntilNextAuthorityBaseline() async {
        let store = NativeSessionStore()
        let sessionID = "failed-live-window"
        store.open(sessionID: sessionID, using: RejectingSessionAPI(promptReachedFacade: nil), endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) {
            if case .failed = store.phase { return true }
            return false
        }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: sessionID,
            seq: 1,
            type: "user/message",
            data: .object([
                "id": .string("must-not-append"),
                "content": .array([.object(["type": .string("text"), "text": .string("must wait for authority")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: sessionID)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.chatNodes.isEmpty)
        XCTAssertTrue(store.trajectoryNodes.isEmpty)
        if case .failed = store.phase {
            // Expected RC8 error state remains stable until the next open/resync.
        } else {
            XCTFail("failed authority window must not become ready from a live frame")
        }
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

    func testSessionSwitchCancelsPendingPromptBeforeLateAcceptanceCanClearNewDraft() async {
        let oldPromptReached = expectation(description: "old prompt reaches Host before session switch")
        let oldPromptCancelled = expectation(description: "old prompt Task cancels when session changes")
        let api = DelayedPromptSessionAPI(oldPromptReached: oldPromptReached, oldPromptCancelled: oldPromptCancelled)
        let store = NativeSessionStore()
        store.open(sessionID: "old-prompt-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: "old-prompt-session") }
        store.draft = "old draft"
        store.submitDraft()
        await fulfillment(of: [oldPromptReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingPrompt)

        store.open(sessionID: "new-prompt-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        store.draft = "new draft"
        await fulfillment(of: [oldPromptCancelled], timeout: 1)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: "new-prompt-session") }

        XCTAssertEqual(store.draft, "new draft")
        XCTAssertFalse(store.isSubmittingPrompt)
        XCTAssertEqual(store.selectedSessionID, "new-prompt-session")
    }

    func testDisconnectCancelsPendingPromptBeforeLateAcceptanceCanReviveBusyState() async {
        let promptReached = expectation(description: "prompt reaches Host before disconnect")
        let promptCancelled = expectation(description: "prompt Task cancels on disconnect")
        let api = DelayedPromptSessionAPI(oldPromptReached: promptReached, oldPromptCancelled: promptCancelled)
        let store = NativeSessionStore()
        let sessionID = "disconnect-prompt-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }
        store.draft = "retry after reconnect"
        store.submitDraft()
        await fulfillment(of: [promptReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingPrompt)

        store.disconnect()
        await fulfillment(of: [promptCancelled], timeout: 1)
        for _ in 0 ..< 20 { await Task.yield() }

        XCTAssertNil(store.selectedSessionID)
        XCTAssertFalse(store.isSubmittingPrompt)
    }

    func testCancelRunningTurnCancelsPendingPromptBeforeLateAcceptanceCanClearDraft() async {
        let promptReached = expectation(description: "prompt reaches Host before turn cancellation")
        let promptCancelled = expectation(description: "pending prompt Task cancels when turn is cancelled")
        let api = DelayedPromptSessionAPI(oldPromptReached: promptReached, oldPromptCancelled: promptCancelled)
        let store = NativeSessionStore()
        let sessionID = "cancel-prompt-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }
        store.draft = "retain after cancel"
        store.submitDraft()
        await fulfillment(of: [promptReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingPrompt)

        store.applyMuxFrame(sessionEventFrame(
            sessionID: sessionID,
            seq: 1,
            type: "turn/start",
            data: .object(["turn": .number(1)])
        ), sessionID: sessionID)
        XCTAssertTrue(store.isRunning)
        store.cancelRunningTurn()
        await fulfillment(of: [promptCancelled], timeout: 1)
        for _ in 0 ..< 20 { await Task.yield() }

        XCTAssertEqual(store.draft, "retain after cancel")
        XCTAssertFalse(store.isSubmittingPrompt)
        XCTAssertEqual(store.selectedSessionID, sessionID)
    }

    func testAdmittedImagePromptUsesTypedHostFacadeWithExactContent() async throws {
        let promptReachedFacade = expectation(description: "typed prompt facade receives admitted image content")
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9UQAAAABJRU5ErkJggg==")!
        let api = AcceptingSessionAPI(
            promptReachedFacade: promptReachedFacade,
            imageLimits: .init(
                maxImageBytes: 4_096,
                maxImagesPerMessage: 2,
                maxMessageImageBytes: 8_192,
                maxImagePixels: 16,
                maxImageDimension: 4,
                mediaTypes: ["image/png"]
            )
        )
        let store = NativeSessionStore()
        let sessionID = "admitted-image-prompt-session"
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-session-image-\(UUID().uuidString).not-an-image")
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.imageAttachmentLimits != nil }
        store.draft = "caption retained in the typed content array"
        store.addPendingImage(imageURL)
        XCTAssertEqual(store.pendingImages.count, 1)

        store.submitDraft()
        await fulfillment(of: [promptReachedFacade], timeout: 1)
        XCTAssertEqual(api.promptSessionIDs, [sessionID])
        XCTAssertEqual(api.promptContents, [[
            .text(text: "caption retained in the typed content array"),
            .image(mediaType: "image/png", data: imageData.base64EncodedString(), name: imageURL.lastPathComponent),
        ]])
        await eventually(timeout: 1) { store.draft.isEmpty && store.pendingImages.isEmpty }
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

    func testSessionSwitchCancelsPendingPermissionCommandBeforeLateAcceptanceCanAffectNewSession() async {
        let commandReached = expectation(description: "permission command reaches Host before session switch")
        let commandCancelled = expectation(description: "permission command Task cancels on session switch")
        let api = DelayedPromptSessionAPI(oldPromptReached: commandReached, oldPromptCancelled: commandCancelled)
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let oldSessionID = tryUnwrap(store.selectedSessionID)
        store.projections.apply(
            sessionID: oldSessionID,
            key: "permissions",
            value: .object([
                "options": .array([
                    .object(["value": .string("workspace-write"), "name": .string("workspace-write")]),
                    .object(["value": .string("danger-full-access"), "name": .string("danger-full-access")]),
                ]),
                "currentValue": .string("workspace-write"),
            ]),
            seq: 12
        )
        store.setSessionAPIForTesting(api)
        store.selectPermissionPreset("danger-full-access")
        await fulfillment(of: [commandReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingPermission)

        store.open(sessionID: "new-permission-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await fulfillment(of: [commandCancelled], timeout: 1)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: "new-permission-session") }

        XCTAssertFalse(store.isSubmittingPermission)
        XCTAssertEqual(store.selectedSessionID, "new-permission-session")
        XCTAssertNil(store.extensionState?.permissions)
    }

    func testKnownUnroutableModelDirectoryBlocksPromptUntilHostReloadRestoresRoute() async {
        let api = PromptRouteSessionAPI()
        let store = NativeSessionStore()
        store.open(sessionID: "model-blocked-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.modelDirectory?.routable == false }
        XCTAssertFalse(store.isPromptRouteAvailable)
        store.draft = "do not send without a Host route"
        store.submitDraft()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(api.promptContents.isEmpty)
        XCTAssertEqual(store.draft, "do not send without a Host route")

        api.routable = true
        store.reloadModelDirectory()
        await eventually(timeout: 1) { store.isPromptRouteAvailable }
        store.submitDraft()
        await eventually(timeout: 1) { api.promptContents.count == 1 }
        XCTAssertEqual(api.promptContents, [[.text(text: "do not send without a Host route")]])
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

    func testAuthorityRecoveryResyncsObservedSubagentCatalogsFromHost() async {
        let rootID = "recovery-session"
        let childID = "child-parent"
        let rootInitial = SubagentListResponse(entries: [
            .init(kind: "child", id: childID, activity: "inactive", hasChildren: true, mode: "continuable", label: "Initial child", reason: nil),
        ], parentAvailable: true)
        let childInitial = SubagentListResponse(entries: [
            .init(kind: "child", id: "old-grandchild", activity: "inactive", hasChildren: false, mode: "one-shot", label: "Old descendant", reason: nil),
        ], parentAvailable: true)
        let rootRecovered = SubagentListResponse(entries: [
            .init(kind: "child", id: childID, activity: "running", hasChildren: true, mode: "continuable", label: "Recovered child", reason: nil),
        ], parentAvailable: false)
        let childRecovered = SubagentListResponse(entries: [
            .init(kind: "child", id: "new-grandchild", activity: "running", hasChildren: false, mode: "one-shot", label: "New descendant", reason: nil),
        ], parentAvailable: true)
        let recoveryHistory = expectation(description: "gap recovery reaches history")
        let api = RecordingSubagentCatalogAPI(catalogs: [rootID: rootInitial, childID: childInitial])
        let store = NativeSessionStore()
        store.open(
            sessionID: rootID,
            using: GapRecoveringSessionAPI(recoveryReachedHistory: recoveryHistory),
            endpoint: URL(string: "http://127.0.0.1:1")!,
            subagentCatalogAPI: api
        )
        store.refreshSubagentCatalog()
        await eventually(timeout: 1) { store.subagentCatalogs[rootID] == rootInitial }
        store.refreshSubagentCatalog(parentSessionID: childID)
        await eventually(timeout: 1) { store.subagentCatalogs[childID] == childInitial }

        api.catalogs = [rootID: rootRecovered, childID: childRecovered]
        store.applyMuxFrame(sessionEventFrame(
            sessionID: rootID,
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("catalog-recovery-gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("trigger catalog recovery")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: rootID)
        await fulfillment(of: [recoveryHistory], timeout: 1)
        await eventually(timeout: 1) {
            store.subagentCatalogs[rootID] == rootRecovered && store.subagentCatalogs[childID] == childRecovered
        }

        XCTAssertEqual(api.parentIDs.count, 4)
        XCTAssertEqual(Set(api.parentIDs.suffix(2)), Set([rootID, childID]))
        XCTAssertFalse(store.subagentCatalogs.keys.contains("new-grandchild"), "recovery must not infer a grandchild catalog without an explicit Host list")
    }

    func testAuthorityRecoveryResyncsSelectedSubagentParentCatalog() async {
        let childID = "selected-child"
        let parentID = "selected-parent"
        let parentCatalog = SubagentListResponse(entries: [
            .init(kind: "child", id: childID, activity: "running", hasChildren: false, mode: "continuable", label: "Recovered selected child", reason: nil),
        ], parentAvailable: true)
        let childCatalog = SubagentListResponse(entries: [], parentAvailable: true)
        let recoveryHistory = expectation(description: "selected child gap reaches recovery history")
        let api = RecordingSubagentCatalogAPI(catalogs: [parentID: parentCatalog, childID: childCatalog])
        let store = NativeSessionStore()
        store.open(
            sessionID: childID,
            using: GapRecoveringSessionAPI(recoveryReachedHistory: recoveryHistory),
            endpoint: URL(string: "http://127.0.0.1:1")!,
            subagentCatalogAPI: api
        )
        await eventually(timeout: 1) { store.phase == .ready(sessionID: childID) }
        store.setSubagentRoute(
            parentSessionID: parentID,
            entry: .init(kind: "child", id: childID, activity: "running", hasChildren: false, mode: "continuable", label: nil, reason: nil),
            parentAvailable: true
        )

        store.applyMuxFrame(sessionEventFrame(
            sessionID: childID,
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("selected-child-gap"),
                "content": .array([.object(["type": .string("text"), "text": .string("trigger selected child recovery")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: childID)
        await fulfillment(of: [recoveryHistory], timeout: 1)
        await eventually(timeout: 1) { store.subagentCatalogs[parentID] == parentCatalog }

        XCTAssertEqual(Set(api.parentIDs), Set([childID, parentID]))
        XCTAssertEqual(store.subagentCatalogs[parentID]?.entries.first?.label, "Recovered selected child")
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
        let sessionAPI = RejectingSessionAPI(promptReachedFacade: nil, opensAuthority: true)
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

    func testEarlySubscriptionWatermarkTriggersSecondPullAfterInitialHistoryInstall() async {
        let initialHistoryReached = expectation(description: "initial history is held until subscription arrives")
        let api = DelayedOpeningHistorySessionAPI(staleHistoryReached: initialHistoryReached)
        let store = NativeSessionStore()
        let sessionID = "early-subscription-stitch"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await fulfillment(of: [initialHistoryReached], timeout: 1)

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "early-ahead-subscription", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string(sessionID),
            "lastSeq": .number(2),
        ])), sessionID: sessionID)
        await api.releaseHistory()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["resynced authority"]
                && store.modelDirectory?.current.model == "resynced-model"
        }

        XCTAssertEqual(api.historyCalls, 2, "RC8 requires a second history pull after early subscribed.lastSeq exceeds the installed tail")
        XCTAssertEqual(store.items.map(\.sequence), [2])
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
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: "recovery-session") && store.items.map(\.text) == ["baseline"]
        }

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
                && store.items.map(\.sequence) == [1, 2, 3]
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

        // RC8's JS memo references are runtime-specific. The Native continuous
        // reference instead compares the published typed projection after the
        // same authority baseline and post-cut live tail arrive without a gap.
        let continuous = NativeSessionStore()
        let continuousAPI = ContinuousAuthoritySessionAPI()
        continuous.open(sessionID: "recovery-session", using: continuousAPI, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { continuous.items.map(\.sequence) == [1, 2] }
        continuous.applyMuxFrame(sessionEventFrame(
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
        await eventually(timeout: 1) { continuous.items.map(\.sequence) == [1, 2, 3] }

        XCTAssertEqual(store.items.map { "\($0.sequence):\($0.text)" }, continuous.items.map { "\($0.sequence):\($0.text)" })
        XCTAssertEqual(store.modelDirectory?.current, continuous.modelDirectory?.current)
        XCTAssertEqual(store.modelDirectoryStatus, continuous.modelDirectoryStatus)
        // RC8 consumes the subscription-tail mismatch with exactly one fenced
        // follow-up authority pull after the restart baseline installs; the
        // converged page owns the final transcript, so the visible window is
        // stable across scheduler ordering instead of transiently stitched.
        XCTAssertEqual(api.historyCount, 4)
    }

    func testResidentResyncSupersedesInFlightGapRepairAndDropsItsLiveBuffer() async {
        let staleHistoryReached = expectation(description: "gap repair history is delayed")
        let resyncedHistoryReached = expectation(description: "resident resync issues newer authority history")
        let api = SupersedingGapRecoverySessionAPI(
            staleHistoryReached: staleHistoryReached,
            newHistoryReached: resyncedHistoryReached
        )
        let store = NativeSessionStore()
        let sessionID = "resident-resync-gap-repair"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) && store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(sessionEventFrame(
            sessionID: sessionID,
            seq: 3,
            type: "user/message",
            data: .object([
                "id": .string("obsolete-gap-tail"),
                "content": .array([.object(["type": .string("text"), "text": .string("must be dropped by full resync")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: sessionID)
        await fulfillment(of: [staleHistoryReached], timeout: 1)

        store.resyncActiveSession()
        await fulfillment(of: [resyncedHistoryReached], timeout: 1)
        await api.releaseStaleHistory()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["baseline", "new host authority"]
                && store.modelDirectory?.current.model == "model-new"
        }
        XCTAssertFalse(store.items.contains(where: { $0.text == "must be dropped by full resync" }))
        XCTAssertEqual(store.items.map(\.sequence), [1, 2])
    }

    func testResidentResyncSupersedesInFlightWatermarkSecondPull() async {
        let staleHistoryReached = expectation(description: "watermark second pull history is delayed")
        let resyncedHistoryReached = expectation(description: "resident resync replaces watermark authority")
        let api = SupersedingGapRecoverySessionAPI(
            staleHistoryReached: staleHistoryReached,
            newHistoryReached: resyncedHistoryReached
        )
        let store = NativeSessionStore()
        let sessionID = "resident-resync-watermark"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) && store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "ahead-watermark", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string(sessionID),
            "lastSeq": .number(2),
        ])), sessionID: sessionID)
        await fulfillment(of: [staleHistoryReached], timeout: 1)

        store.resyncActiveSession()
        await fulfillment(of: [resyncedHistoryReached], timeout: 1)
        await api.releaseStaleHistory()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["baseline", "new host authority"]
                && store.modelDirectory?.current.model == "model-new"
        }
        XCTAssertFalse(store.items.contains(where: { $0.text == "stale authority" }))
    }

    func testAheadWatermarkFailureKeepsFirstWindowReady() async {
        let recoveryHistoryReached = expectation(description: "ahead watermark recovery history is held")
        let api = CoalescingGapFailureSessionAPI(recoveryHistoryReached: recoveryHistoryReached)
        let store = NativeSessionStore()
        let sessionID = "recovery-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "ahead-watermark-failure", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string(sessionID),
            "lastSeq": .number(2),
        ])), sessionID: sessionID)
        await fulfillment(of: [recoveryHistoryReached], timeout: 1)
        await api.failRecovery()
        await eventually(timeout: 1) {
            if case .error = store.modelDirectoryStatus { return true }
            return false
        }

        XCTAssertEqual(api.historyCalls, 2)
        XCTAssertEqual(store.items.map(\.text), ["baseline"])
        XCTAssertEqual(store.phase, .ready(sessionID: sessionID))
    }

    func testColdOpenStitchesBufferedLiveTailAfterHistoryAuthority() async {
        let historyReached = expectation(description: "cold history is delayed")
        let api = DelayedOpeningHistorySessionAPI(staleHistoryReached: historyReached)
        let store = NativeSessionStore()
        let sessionID = "cold-stitch-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await fulfillment(of: [historyReached], timeout: 1)

        store.applyMuxFrame(sessionEventFrame(
            sessionID: sessionID,
            seq: 1,
            type: "user/message",
            data: .object([
                "id": .string("page-overlap"),
                "content": .array([.object(["type": .string("text"), "text": .string("must not replace history")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: sessionID)
        store.applyMuxFrame(sessionEventFrame(
            sessionID: sessionID,
            seq: 2,
            type: "user/message",
            data: .object([
                "id": .string("live-tail"),
                "content": .array([.object(["type": .string("text"), "text": .string("live tail")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: sessionID)
        await api.releaseHistory()
        await eventually(timeout: 1) { store.items.map(\.text) == ["stale authority", "live tail"] }

        XCTAssertEqual(store.items.map(\.sequence), [1, 2])
        XCTAssertEqual(store.phase, .ready(sessionID: sessionID))
        XCTAssertEqual(store.chatNodes.compactMap { $0.data as? CoreUserMessageNode }.map(\.seq), [1, 2])
    }

    func testNewEndpointOpenSupersedesStaleInitialHistoryAuthority() async {
        let staleHistoryReached = expectation(description: "stale initial history is delayed")
        let staleAPI = DelayedOpeningHistorySessionAPI(staleHistoryReached: staleHistoryReached)
        let freshAPI = FixedOpeningSessionAPI(model: "fresh-model", text: "fresh authority")
        let store = NativeSessionStore()
        let sessionID = "recovery-session"
        let staleEndpoint = URL(string: "http://127.0.0.1:1")!
        let freshEndpoint = URL(string: "http://127.0.0.1:2")!

        store.open(sessionID: sessionID, using: staleAPI, endpoint: staleEndpoint)
        await fulfillment(of: [staleHistoryReached], timeout: 1)
        store.open(sessionID: sessionID, using: freshAPI, endpoint: freshEndpoint)
        await eventually(timeout: 1) {
            store.items.map(\.text) == ["fresh authority"] && store.modelDirectory?.current.model == "fresh-model"
        }

        await staleAPI.releaseHistory()
        await eventually(timeout: 1) {
            store.items.map(\.text) == ["fresh authority"] && store.modelDirectory?.current.model == "fresh-model"
        }
        XCTAssertEqual(store.selectedSessionID, sessionID)
        XCTAssertEqual(store.modelDirectoryStatus, .ready)
    }

    func testResidentResyncSupersedesStaleInitialHistoryOnSameEndpoint() async {
        let staleHistoryReached = expectation(description: "same-endpoint initial history is delayed")
        let api = DelayedOpeningHistorySessionAPI(staleHistoryReached: staleHistoryReached)
        let store = NativeSessionStore()
        let sessionID = "resident-resync-stale-open"
        let endpoint = URL(string: "http://127.0.0.1:1")!

        store.open(sessionID: sessionID, using: api, endpoint: endpoint)
        await fulfillment(of: [staleHistoryReached], timeout: 1)
        store.resyncActiveSession()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["resynced authority"]
                && store.modelDirectory?.current.model == "resynced-model"
        }

        await api.releaseHistory()
        await eventually(timeout: 1) {
            store.items.map(\.text) == ["resynced authority"]
                && store.modelDirectory?.current.model == "resynced-model"
        }
        XCTAssertEqual(api.historyCalls, 2)
        XCTAssertEqual(store.modelDirectoryStatus, .ready)
    }

    func testResidentResyncIgnoresLateFailureFromStaleInitialHistory() async {
        let staleHistoryReached = expectation(description: "same-endpoint stale history waits before failure")
        let api = DelayedOpeningHistorySessionAPI(staleHistoryReached: staleHistoryReached, failStaleHistory: true)
        let store = NativeSessionStore()
        let sessionID = "resident-resync-stale-failure"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await fulfillment(of: [staleHistoryReached], timeout: 1)

        store.resyncActiveSession()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["resynced authority"]
                && store.modelDirectory?.current.model == "resynced-model"
        }
        await api.releaseHistory()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["resynced authority"]
                && store.modelDirectory?.current.model == "resynced-model"
        }
    }

    func testConcurrentGapFramesCoalesceIntoOneAuthorityRecovery() async {
        let recoveryHistoryReached = expectation(description: "first gap recovery history is held")
        let api = CoalescingGapFailureSessionAPI(recoveryHistoryReached: recoveryHistoryReached)
        let store = NativeSessionStore()
        store.open(sessionID: "recovery-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline"] }

        for (sequence, text) in [(3, "first buffered gap"), (4, "second buffered gap")] {
            store.applyMuxFrame(sessionEventFrame(
                sessionID: "recovery-session",
                seq: sequence,
                type: "user/message",
                data: .object([
                    "id": .string("coalesced-\(sequence)"),
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: "append"
            ), sessionID: "recovery-session")
        }
        await fulfillment(of: [recoveryHistoryReached], timeout: 1)
        XCTAssertEqual(api.historyCalls, 2, "concurrent gaps must reuse the existing authority recovery")
        XCTAssertEqual(store.items.map(\.text), ["baseline"])

        await api.failRecovery()
        await eventually(timeout: 1) {
            if case .error = store.modelDirectoryStatus { return true }
            return false
        }
        XCTAssertEqual(api.historyCalls, 2)
        XCTAssertEqual(store.items.map(\.text), ["baseline"])
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

    func testLiveEventGapRecoversAuthorityWindowThenStitchesPostCutTail() async {
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
                "content": .array([.object(["type": .string("text"), "text": .string("post-cut tail")])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: "append"
        ), sessionID: "recovery-session")
        await fulfillment(of: [recoveryReachedHistory], timeout: 1)
        await eventually(timeout: 1) { store.items.map(\.text) == ["baseline", "recovered authority", "post-cut tail"] }

        XCTAssertEqual(store.items.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(store.items.last?.text, "post-cut tail")
        XCTAssertEqual(store.chatNodes.compactMap { $0.data as? CoreUserMessageNode }.map(\.seq), [1, 2, 3])
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

    func testQueueEditFailureIsScopedToTheActionAndRetainsHostRowForRetry() async {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-edit-reject", messageID: "m-edit-reject", placement: "queued", content: [.object(["type": .string("text"), "text": .string("original Host queue row")])]),
        ]), sessionID: sessionID)
        let invoked = expectation(description: "rejected queue edit reaches typed session facade")
        let api = RecordingQueueSessionAPI(invoked: invoked, error: DSHTransportError.invalidEndpoint)
        store.setSessionAPIForTesting(api)

        store.updateQueuedMessage(itemID: "q-edit-reject", action: .edit(content: [.text(text: "edited")]))
        await fulfillment(of: [invoked], timeout: 1)
        await eventually(timeout: 1) { store.updatingQueueItemID == nil }

        XCTAssertEqual(store.queueActionFailure, .init(itemID: "q-edit-reject", kind: .edit))
        XCTAssertNil(store.queueActionCompletion)
        XCTAssertEqual(store.queuedMessages.map(\.preview), ["original Host queue row"])
    }

    func testLateQueueReceiptDoesNotCompleteRowAlreadyRetiredByHostSnapshot() async {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-race", messageID: "m-race", placement: "queued", content: [.object(["type": .string("text"), "text": .string("Host owns retirement")])]),
        ]), sessionID: sessionID)
        let reached = expectation(description: "queue action reaches Host before late receipt")
        let api = DelayedQueueSessionAPI(reached: reached)
        store.setSessionAPIForTesting(api)

        store.updateQueuedMessage(itemID: "q-race", action: .remove)
        await fulfillment(of: [reached], timeout: 1)
        XCTAssertEqual(store.updatingQueueItemID, "q-race")

        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: []), sessionID: sessionID)
        XCTAssertTrue(store.queuedMessages.isEmpty)
        await api.release()
        await eventually(timeout: 1) { store.updatingQueueItemID == nil }

        XCTAssertNil(store.queueActionCompletion)
        XCTAssertNil(store.queueActionFailure)
        XCTAssertTrue(store.queuedMessages.isEmpty)
    }

    func testLateSteerReceiptDoesNotCompleteRowAlreadyRetiredByHostSnapshot() async {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-steer-race", messageID: "m-steer-race", placement: "queued", content: [.object(["type": .string("text"), "text": .string("Host owns steering retirement")])]),
        ]), sessionID: sessionID)
        let reached = expectation(description: "steer reaches Host before late receipt")
        let api = DelayedQueueSessionAPI(reached: reached)
        store.setSessionAPIForTesting(api)

        store.updateQueuedMessage(itemID: "q-steer-race", action: .steer)
        await fulfillment(of: [reached], timeout: 1)
        XCTAssertEqual(store.updatingQueueItemID, "q-steer-race")

        // The following whole snapshot is authority. A later accepted receipt
        // cannot recreate a row that Host has already moved or retired.
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: []), sessionID: sessionID)
        XCTAssertTrue(store.queuedMessages.isEmpty)
        await api.release()
        await eventually(timeout: 1) { store.updatingQueueItemID == nil }

        XCTAssertNil(store.queueActionCompletion)
        XCTAssertNil(store.queueActionFailure)
        XCTAssertTrue(store.queuedMessages.isEmpty)
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

    func testSteerFailureIsScopedToTheActionAndDoesNotRetireHostRow() async {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = tryUnwrap(store.selectedSessionID)
        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "q-steer-reject", messageID: "m-steer-reject", placement: "queued", content: [.object(["type": .string("text"), "text": .string("retry after rejection")])]),
        ]), sessionID: sessionID)
        let invoked = expectation(description: "steer reaches typed session facade")
        let api = RecordingQueueSessionAPI(invoked: invoked, error: DSHTransportError.invalidEndpoint)
        store.setSessionAPIForTesting(api)

        store.updateQueuedMessage(itemID: "q-steer-reject", action: .steer)
        await fulfillment(of: [invoked], timeout: 1)
        await eventually(timeout: 1) { store.updatingQueueItemID == nil }

        XCTAssertEqual(api.requests, [.init(sessionId: sessionID, itemId: "q-steer-reject", action: .steer)])
        XCTAssertEqual(store.queueActionFailure, .init(itemID: "q-steer-reject", kind: .steer))
        XCTAssertNil(store.queueActionCompletion)
        XCTAssertEqual(store.queuedMessages.map(\.id), ["q-steer-reject"])
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

    func testSubscriptionRestartClearsPendingInteractionsUntilHostReplay() {
        let store = NativeSessionStore()
        let sessionID = "snapshot-tooling"
        store.loadSnapshotToolingFixture()
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "restart-approval", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"),
            "sessionId": .string(sessionID),
            "approvalId": .string("restart-approval-id"),
            "toolName": .string("bash"),
        ])), sessionID: sessionID)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "restart-question", method: "question/requested", payload: .object([
            "type": .string("question/requested"),
            "sessionId": .string(sessionID),
            "questions": .array([.object([
                "id": .string("restart-question-id"),
                "question": .string("Replayed after reconnect?"),
                "options": .array([.object(["label": .string("Yes")])]),
            ])]),
        ])), sessionID: sessionID)
        XCTAssertNotNil(store.pendingApproval)
        XCTAssertNotNil(store.pendingQuestion)

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "restart-subscription", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string(sessionID),
            "lastSeq": .number(0),
        ])), sessionID: sessionID)

        XCTAssertNil(store.pendingApproval)
        XCTAssertNil(store.pendingQuestion)
        XCTAssertFalse(store.isSubmittingApproval)
        XCTAssertFalse(store.isSubmittingQuestion)
    }

    func testResidentResyncRebuildsWindowClearsPendingAndColdInstanceNoOps() async {
        let cold = NativeSessionStore()
        cold.resyncActiveSession()
        XCTAssertNil(cold.selectedSessionID)
        XCTAssertTrue(cold.chatNodes.isEmpty)

        let resyncHistoryReached = expectation(description: "resident resync reaches Host history")
        let api = GatedResidentResyncSessionAPI(resyncHistoryReached: resyncHistoryReached)
        let store = NativeSessionStore()
        let sessionID = "resident-resync-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) && store.items.map(\.text) == ["initial authority"] }

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "stale-approval", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"),
            "sessionId": .string(sessionID),
            "approvalId": .string("approval-1"),
            "toolName": .string("bash"),
        ])), sessionID: sessionID)
        XCTAssertNotNil(store.pendingApproval)

        store.resyncActiveSession()
        await fulfillment(of: [resyncHistoryReached], timeout: 1)
        XCTAssertEqual(store.phase, .loading(sessionID: sessionID))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.chatNodes.isEmpty)
        XCTAssertFalse(store.hasMoreHistory)
        XCTAssertNil(store.pendingApproval)
        XCTAssertNil(store.pendingQuestion)
        XCTAssertFalse(store.isSubmittingApproval)
        XCTAssertFalse(store.isSubmittingQuestion)

        await api.releaseResyncHistory()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["resynced authority"]
        }
        XCTAssertEqual(api.historyCalls, 2)
        XCTAssertEqual(api.modelsCalls, 2)
    }

    func testEarlySubscriptionDuringResidentResyncTriggersFollowUpAuthorityPull() async {
        let resyncHistoryReached = expectation(description: "resident resync history is held for early subscription")
        let api = GatedResidentResyncSessionAPI(resyncHistoryReached: resyncHistoryReached)
        let store = NativeSessionStore()
        let sessionID = "resident-resync-early-subscription"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }

        store.resyncActiveSession()
        await fulfillment(of: [resyncHistoryReached], timeout: 1)
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "resync-early-subscription", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string(sessionID),
            "lastSeq": .number(4),
        ])), sessionID: sessionID)
        await api.releaseResyncHistory()
        await eventually(timeout: 1) {
            store.phase == .ready(sessionID: sessionID)
                && store.items.map(\.text) == ["follow-up authority"]
                && api.historyCalls == 3
                && api.modelsCalls == 3
        }
        XCTAssertEqual(store.items.map(\.sequence), [4])
    }

    func testResidentResyncRetainsQueueAndJobsUntilFreshSubscriptionBoundary() async {
        let resyncHistoryReached = expectation(description: "resident resync is held before fresh subscription")
        let api = GatedResidentResyncSessionAPI(resyncHistoryReached: resyncHistoryReached)
        let store = NativeSessionStore()
        let sessionID = "resident-status-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }

        store.applyMuxFrame(queueFrame(sessionID: sessionID, items: [
            queuedItem(id: "prior-queue", messageID: "prior-message", placement: "queued", content: [.object(["type": .string("text"), "text": .string("retain until subscribed")])]),
        ]), sessionID: sessionID)
        store.applyMuxFrame(jobsFrame(sessionID: sessionID, jobs: [
            job(id: "prior-job", status: "running", startedAt: 1),
        ]), sessionID: sessionID)
        XCTAssertEqual(store.queuedMessages.map(\.id), ["prior-queue"])
        XCTAssertEqual(store.backgroundJobs.map(\.id), ["prior-job"])

        store.resyncActiveSession()
        await fulfillment(of: [resyncHistoryReached], timeout: 1)
        XCTAssertEqual(store.queuedMessages.map(\.id), ["prior-queue"], "RC8 preserves the mirror until the ordered subscription baseline")
        XCTAssertEqual(store.backgroundJobs.map(\.id), ["prior-job"])

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "fresh-subscription", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string(sessionID),
            "lastSeq": .number(0),
        ])), sessionID: sessionID)
        XCTAssertTrue(store.queuedMessages.isEmpty)
        XCTAssertTrue(store.backgroundJobs.isEmpty)

        await api.releaseResyncHistory()
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }
    }

    func testLoadOlderHistoryGuardsKeepWindowAndAdoptEmptyPageHasMore() async {
        let cold = NativeSessionStore()
        cold.loadOlderHistory()
        XCTAssertFalse(cold.isLoadingOlderHistory)
        XCTAssertFalse(cold.hasMoreHistory)

        let api = PagingHistorySessionAPI()
        let store = NativeSessionStore()
        let sessionID = "paging-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }
        XCTAssertEqual(api.historyBeforeSequences, [nil])
        XCTAssertEqual(store.chatNodes.count, 1)
        XCTAssertTrue(store.hasMoreHistory)

        api.enqueuePage(.failure)
        store.loadOlderHistory()
        await eventually(timeout: 1) { api.historyBeforeSequences.count == 2 && !store.isLoadingOlderHistory }
        XCTAssertEqual(store.chatNodes.count, 1)
        XCTAssertTrue(store.hasMoreHistory)

        api.enqueuePage(.empty(hasMore: false))
        store.loadOlderHistory()
        await eventually(timeout: 1) { api.historyBeforeSequences.count == 3 && !store.isLoadingOlderHistory }
        XCTAssertEqual(store.chatNodes.count, 1)
        XCTAssertFalse(store.hasMoreHistory)

        let exhaustedCalls = api.historyBeforeSequences.count
        store.loadOlderHistory()
        XCTAssertEqual(api.historyBeforeSequences.count, exhaustedCalls)
        XCTAssertFalse(store.isLoadingOlderHistory)
    }

    func testReplayedQuestionKeepsNewBusyStateWhenOldSubmissionFailsLate() async {
        let oldAnswerReached = expectation(description: "old answer reaches Host before restart")
        let oldAnswerCancelled = expectation(description: "old answer Task cancels when Host restart replaces pending request")
        let api = DelayedReplayedQuestionSessionAPI(
            oldAnswerReached: oldAnswerReached,
            oldAnswerCancelled: oldAnswerCancelled
        )
        let store = NativeSessionStore()
        let sessionID = "replayed-question-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }

        let questionFrame = RPCServerRequest(type: "server-request", rpcId: "replayed-question", method: "question/requested", payload: .object([
            "type": .string("question/requested"),
            "sessionId": .string(sessionID),
            "questions": .array([.object(["id": .string("q-1"), "question": .string("Proceed?")])]),
        ]))
        store.applyMuxFrame(questionFrame, sessionID: sessionID)
        store.answerQuestion([.init(id: "q-1", selected: ["yes"], custom: nil)])
        await fulfillment(of: [oldAnswerReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingQuestion)

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "restart", method: "session/subscribed", payload: .object([
            "type": .string("session/subscribed"),
            "sessionId": .string(sessionID),
            "lastSeq": .number(0),
        ])), sessionID: sessionID)
        await eventually(timeout: 1) { store.pendingQuestion == nil && !store.isSubmittingQuestion }
        await fulfillment(of: [oldAnswerCancelled], timeout: 1)
        store.applyMuxFrame(questionFrame, sessionID: sessionID)
        store.answerQuestion([.init(id: "q-1", selected: ["yes"], custom: nil)])
        await eventually(timeout: 1) { store.isSubmittingQuestion }

        await api.failOldAnswer()
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(api.answerCalls, 2)
        XCTAssertEqual(store.pendingQuestion?.rpcID, "replayed-question")
        XCTAssertTrue(store.isSubmittingQuestion)
    }

    func testDisconnectCancelsPendingApprovalSubmissionBeforeLateFailure() async {
        let oldApprovalReached = expectation(description: "approval reaches Host before disconnect")
        let oldApprovalCancelled = expectation(description: "approval submission cancels on disconnect")
        let api = DelayedReplacingApprovalSessionAPI(
            oldApprovalReached: oldApprovalReached,
            oldApprovalCancelled: oldApprovalCancelled
        )
        let store = NativeSessionStore()
        let sessionID = "disconnected-approval-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "approval-rpc", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"),
            "sessionId": .string(sessionID),
            "approvalId": .string("approval-id"),
            "toolName": .string("bash"),
        ])), sessionID: sessionID)

        store.answerApproval(allowOnce: true)
        await fulfillment(of: [oldApprovalReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingApproval)

        store.disconnect()
        await fulfillment(of: [oldApprovalCancelled], timeout: 1)
        for _ in 0 ..< 20 { await Task.yield() }

        XCTAssertNil(store.selectedSessionID)
        XCTAssertNil(store.pendingApproval)
        XCTAssertFalse(store.isSubmittingApproval)
    }

    func testReplacingApprovalCancelsOldSubmissionBeforeItCanMutateNewRequest() async {
        let oldApprovalReached = expectation(description: "old approval reaches Host before pending replacement")
        let oldApprovalCancelled = expectation(description: "old approval Task cancels when a new approval replaces it")
        let api = DelayedReplacingApprovalSessionAPI(
            oldApprovalReached: oldApprovalReached,
            oldApprovalCancelled: oldApprovalCancelled
        )
        let store = NativeSessionStore()
        let sessionID = "replaced-approval-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }

        func approvalFrame(rpcID: String, approvalID: String) -> RPCServerRequest {
            .init(type: "server-request", rpcId: rpcID, method: "approval/requested", payload: .object([
                "type": .string("approval/requested"),
                "sessionId": .string(sessionID),
                "approvalId": .string(approvalID),
                "toolName": .string("bash"),
            ]))
        }

        store.applyMuxFrame(approvalFrame(rpcID: "approval-old", approvalID: "old-id"), sessionID: sessionID)
        store.answerApproval(allowOnce: true)
        await fulfillment(of: [oldApprovalReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingApproval)

        store.applyMuxFrame(approvalFrame(rpcID: "approval-new", approvalID: "new-id"), sessionID: sessionID)
        await fulfillment(of: [oldApprovalCancelled], timeout: 1)
        XCTAssertEqual(store.pendingApproval?.rpcID, "approval-new")
        XCTAssertEqual(store.pendingApproval?.approvalID, "new-id")
        XCTAssertFalse(store.isSubmittingApproval)

        store.answerApproval(allowOnce: false)
        await eventually(timeout: 1) { api.approvalCalls == 2 && store.isSubmittingApproval }
        XCTAssertEqual(store.pendingApproval?.rpcID, "approval-new")
        XCTAssertTrue(store.isSubmittingApproval)
    }

    func testDisconnectCancelsPendingQuestionCancellationBeforeLateFailure() async {
        let cancellationReached = expectation(description: "question cancellation reaches Host before disconnect")
        let cancellationCancelled = expectation(description: "question cancellation Task cancels on disconnect")
        let api = DelayedReplacingQuestionCancelSessionAPI(
            oldCancellationReached: cancellationReached,
            oldCancellationCancelled: cancellationCancelled
        )
        let store = NativeSessionStore()
        let sessionID = "disconnected-question-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }
        store.applyMuxFrame(.init(type: "server-request", rpcId: "question-rpc", method: "question/requested", payload: .object([
            "type": .string("question/requested"),
            "sessionId": .string(sessionID),
            "questions": .array([.object(["id": .string("q-1"), "question": .string("Proceed?")])]),
        ])), sessionID: sessionID)

        store.cancelQuestion()
        await fulfillment(of: [cancellationReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingQuestion)

        store.disconnect()
        await fulfillment(of: [cancellationCancelled], timeout: 1)
        for _ in 0 ..< 20 { await Task.yield() }

        XCTAssertNil(store.selectedSessionID)
        XCTAssertNil(store.pendingQuestion)
        XCTAssertFalse(store.isSubmittingQuestion)
    }

    func testReplacingQuestionCancelsOldCancellationBeforeItCanMutateNewRequest() async {
        let oldCancellationReached = expectation(description: "old question cancellation reaches Host before pending replacement")
        let oldCancellationCancelled = expectation(description: "old question cancellation Task cancels when a new question replaces it")
        let api = DelayedReplacingQuestionCancelSessionAPI(
            oldCancellationReached: oldCancellationReached,
            oldCancellationCancelled: oldCancellationCancelled
        )
        let store = NativeSessionStore()
        let sessionID = "replaced-question-cancel-session"
        store.open(sessionID: sessionID, using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await eventually(timeout: 1) { store.phase == .ready(sessionID: sessionID) }

        func questionFrame(_ rpcID: String) -> RPCServerRequest {
            .init(type: "server-request", rpcId: rpcID, method: "question/requested", payload: .object([
                "type": .string("question/requested"),
                "sessionId": .string(sessionID),
                "questions": .array([.object(["id": .string("q-1"), "question": .string("Proceed?")])]),
            ]))
        }

        store.applyMuxFrame(questionFrame("question-old"), sessionID: sessionID)
        store.cancelQuestion()
        await fulfillment(of: [oldCancellationReached], timeout: 1)
        XCTAssertTrue(store.isSubmittingQuestion)

        store.applyMuxFrame(questionFrame("question-new"), sessionID: sessionID)
        await fulfillment(of: [oldCancellationCancelled], timeout: 1)
        XCTAssertEqual(store.pendingQuestion?.rpcID, "question-new")
        XCTAssertFalse(store.isSubmittingQuestion)

        store.cancelQuestion()
        await eventually(timeout: 1) { api.cancelCalls == 2 && store.isSubmittingQuestion }
        XCTAssertEqual(store.pendingQuestion?.rpcID, "question-new")
        XCTAssertTrue(store.isSubmittingQuestion)
    }

    func testPendingInteractionAndProjectionFramesHaveExactSnapshotBoundaries() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = "snapshot-tooling"

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "projection-current", method: "session/projection", payload: .object([
            "type": .string("session/projection"), "sessionId": .string(sessionID),
            "key": .string("interaction-matrix"), "value": .string("current"), "seq": .number(8),
        ])), sessionID: sessionID)
        XCTAssertEqual(store.projections.row(sessionID: sessionID, key: "interaction-matrix"), .init(value: .string("current"), seq: 8))

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "projection-stale", method: "session/projection", payload: .object([
            "type": .string("session/projection"), "sessionId": .string(sessionID),
            "key": .string("interaction-matrix"), "value": .string("stale"), "seq": .number(7),
        ])), sessionID: sessionID)
        XCTAssertEqual(store.projections.row(sessionID: sessionID, key: "interaction-matrix"), .init(value: .string("current"), seq: 8))

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "approval-matrix", method: "approval/requested", payload: .object([
            "type": .string("approval/requested"), "sessionId": .string(sessionID),
            "approvalId": .string("approval-matrix"), "toolName": .string("bash"),
        ])), sessionID: sessionID)
        XCTAssertEqual(store.pendingApproval?.rpcID, "approval-matrix")
        XCTAssertNil(store.pendingQuestion)

        // A newer question request is an exclusive Host takeover and clears the
        // prior approval rather than allowing two native interaction surfaces.
        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "question-matrix", method: "question/requested", payload: .object([
            "type": .string("question/requested"), "sessionId": .string(sessionID),
            "questions": .array([.object(["id": .string("q-matrix"), "question": .string("Continue?")])]),
        ])), sessionID: sessionID)
        XCTAssertNil(store.pendingApproval)
        XCTAssertEqual(store.pendingQuestion?.rpcID, "question-matrix")
        XCTAssertEqual(store.pendingQuestion?.items.map(\.id), ["q-matrix"])

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "question-wrong", method: "question/resolved", payload: .object([
            "type": .string("question/resolved"), "sessionId": .string(sessionID), "questionRpcId": .string("other"),
        ])), sessionID: sessionID)
        XCTAssertEqual(store.pendingQuestion?.rpcID, "question-matrix")

        store.applyMuxFrame(RPCServerRequest(type: "server-request", rpcId: "question-right", method: "question/resolved", payload: .object([
            "type": .string("question/resolved"), "sessionId": .string(sessionID), "questionRpcId": .string("question-matrix"),
        ])), sessionID: sessionID)
        XCTAssertNil(store.pendingQuestion)
        XCTAssertNil(store.pendingApproval)
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

    func testSnapshotDeliverablesFixturePublishesReducerOwnedTurnPaths() {
        let store = NativeSessionStore()
        store.loadSnapshotDeliverablesFixture()

        let assistant = tryUnwrap(store.chatNodes.compactMap { $0.data as? CoreAssistantNode }
            .first(where: { $0.messageID == "deliverables-assistant" }))
        XCTAssertEqual(assistant.status, .settled)
        XCTAssertEqual(store.deliverables(forClosingAssistant: assistant), [
            "关于我.md",
            "index.html",
            "long-generated-experience-specification-for-produced-files-overflow.md",
            "styles.css",
            "app.ts",
            "schema.json",
            "README.md",
            "preview.svg",
            "notes.txt",
            "manifest.yaml",
        ])
        XCTAssertEqual(store.toolInvocations.count, 10)
        XCTAssertEqual(store.toolInvocations.map(\.name), Array(repeating: "write", count: 10))
        XCTAssertEqual(store.toolInvocations.map(\.state), Array(repeating: .completed, count: 10))
        XCTAssertEqual(store.toolInvocations.map(\.sequence), Array(stride(from: 303, through: 321, by: 2)))
        XCTAssertFalse(store.isRunning)
        XCTAssertFalse(store.hasMoreHistory)
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
        XCTAssertEqual(store.modelDirectory?.current.model, "deepseek-v4-flash")
        XCTAssertNil(store.modelDirectory?.current.reasoningEffort)
        XCTAssertTrue(store.modelDirectory?.routable == true)
        XCTAssertEqual(store.modelDirectory?.groups.map(\.id), ["deepseek-official"])
        XCTAssertEqual(store.modelDirectory?.groups.first?.models.map(\.id), ["deepseek-v4-flash"])
        XCTAssertEqual(store.modelDirectory?.groups.first?.models.first?.reasoningEfforts, [])
        XCTAssertEqual(store.modelDirectory?.failures, [])
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
        var catalog: SubagentListResponse?
        var catalogs: [String: SubagentListResponse]
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
    private final class DelayedQueueSessionAPI: NativeSessionAPI {
        let reached: XCTestExpectation
        private let gate = RecoveryGate()

        init(reached: XCTestExpectation) {
            self.reached = reached
        }

        func release() async {
            await gate.open()
        }

        func updateQueue(_ request: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            reached.fulfill()
            await gate.wait()
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
    private final class DelayedPromptSessionAPI: NativeSessionAPI {
        let oldPromptReached: XCTestExpectation
        let oldPromptCancelled: XCTestExpectation
        private let gate = RecoveryGate()
        private var promptCalls = 0

        init(oldPromptReached: XCTestExpectation, oldPromptCancelled: XCTestExpectation) {
            self.oldPromptReached = oldPromptReached
            self.oldPromptCancelled = oldPromptCancelled
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [], hasMore: false, projections: nil)
        }
        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }
        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse {
            promptCalls += 1
            if promptCalls == 1 {
                oldPromptReached.fulfill()
                await gate.wait()
                if Task.isCancelled { oldPromptCancelled.fulfill() }
            }
            return .init(accepted: true)
        }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class AcceptingSessionAPI: NativeSessionAPI {
        let promptReachedFacade: XCTestExpectation
        let imageLimits: ImageAttachmentLimits?
        private(set) var promptSessionIDs: [String] = []
        private(set) var promptContents: [[SessionPromptContent]] = []

        init(promptReachedFacade: XCTestExpectation, imageLimits: ImageAttachmentLimits? = nil) {
            self.promptReachedFacade = promptReachedFacade
            self.imageLimits = imageLimits
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            let projections = imageLimits.map {
                SessionProjectionsDTO(asOfSeq: 0, values: [
                    "imageLimits": .object([
                        "maxImageBytes": .number(Double($0.maxImageBytes)),
                        "maxImagesPerMessage": .number(Double($0.maxImagesPerMessage)),
                        "maxMessageImageBytes": .number(Double($0.maxMessageImageBytes)),
                        "maxImagePixels": .number(Double($0.maxImagePixels)),
                        "maxImageDimension": .number(Double($0.maxImageDimension)),
                        "mediaTypes": .array($0.mediaTypes.map(JSONValue.string)),
                    ]),
                ])
            }
            return .init(events: [], hasMore: false, projections: projections)
        }
        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }
        func prompt(sessionID: String, content: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse {
            promptSessionIDs.append(sessionID)
            promptContents.append(content)
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
        private(set) var historyCount = 0
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
            case 3:
                newHistoryReached.fulfill()
                return .init(
                    events: [first, historyEntry(seq: 2, id: "new", text: "new host authority")],
                    hasMore: false,
                    projections: nil
                )
            default:
                // RC8 consumes a subscription-tail mismatch with exactly one
                // bounded follow-up authority pull. A real restarted Host keeps
                // appending to its durable log, so that follow-up page converges
                // and includes the formerly live-only event as durable history;
                // it must never re-fulfill the restart expectation above.
                return .init(
                    events: [
                        first,
                        historyEntry(seq: 2, id: "new", text: "new host authority"),
                        historyEntry(seq: 3, id: "surviving-live-tail", text: "surviving live tail"),
                    ],
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
    private final class ContinuousAuthoritySessionAPI: NativeSessionAPI {
        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [
                historyEntry(seq: 1, id: "baseline", text: "baseline"),
                historyEntry(seq: 2, id: "new", text: "new host authority"),
            ], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(
                current: .init(provider: "provider", model: "model-new", reasoningEffort: nil),
                routable: true,
                groups: [],
                failures: []
            )
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
    private final class GatedResidentResyncSessionAPI: NativeSessionAPI {
        let resyncHistoryReached: XCTestExpectation
        private let historyGate = RecoveryGate()
        private(set) var historyCalls = 0
        private(set) var modelsCalls = 0

        init(resyncHistoryReached: XCTestExpectation) {
            self.resyncHistoryReached = resyncHistoryReached
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCalls += 1
            if historyCalls == 1 {
                return .init(events: [historyEntry(seq: 1, id: "initial", text: "initial authority")], hasMore: true, projections: nil)
            }
            if historyCalls == 2 {
                resyncHistoryReached.fulfill()
                await historyGate.wait()
                return .init(events: [historyEntry(seq: 3, id: "resynced", text: "resynced authority")], hasMore: false, projections: nil)
            }
            return .init(events: [historyEntry(seq: 4, id: "resync-follow-up", text: "follow-up authority")], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsCalls += 1
            return .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func releaseResyncHistory() async {
            await historyGate.open()
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
    private final class PagingHistorySessionAPI: NativeSessionAPI {
        enum PageOutcome {
            case failure
            case empty(hasMore: Bool)
        }

        private var pages: [PageOutcome] = []
        private(set) var historyBeforeSequences: [Int?] = []

        func enqueuePage(_ page: PageOutcome) {
            pages.append(page)
        }

        func history(sessionID _: String, beforeSeq: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyBeforeSequences.append(beforeSeq)
            guard beforeSeq != nil else {
                return .init(events: [historyEntry(seq: 7, id: "newest", text: "newest")], hasMore: true, projections: nil)
            }
            guard !pages.isEmpty else { throw DSHTransportError.invalidEndpoint }
            switch pages.removeFirst() {
            case .failure:
                throw DSHTransportError.invalidEndpoint
            case let .empty(hasMore):
                return .init(events: [], hasMore: hasMore, projections: nil)
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
    private final class DelayedReplacingQuestionCancelSessionAPI: NativeSessionAPI {
        let oldCancellationReached: XCTestExpectation
        let oldCancellationCancelled: XCTestExpectation
        private let oldCancellationGate = RecoveryGate()
        private(set) var cancelCalls = 0

        init(oldCancellationReached: XCTestExpectation, oldCancellationCancelled: XCTestExpectation) {
            self.oldCancellationReached = oldCancellationReached
            self.oldCancellationCancelled = oldCancellationCancelled
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }

        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt {
            cancelCalls += 1
            if cancelCalls == 1 {
                oldCancellationReached.fulfill()
                await oldCancellationGate.wait()
                if Task.isCancelled { oldCancellationCancelled.fulfill() }
                throw DSHTransportError.invalidEndpoint
            }
            return .init(accepted: true, reason: nil)
        }
    }

    @MainActor
    private final class DelayedReplacingApprovalSessionAPI: NativeSessionAPI {
        let oldApprovalReached: XCTestExpectation
        let oldApprovalCancelled: XCTestExpectation
        private let oldApprovalGate = RecoveryGate()
        private(set) var approvalCalls = 0

        init(oldApprovalReached: XCTestExpectation, oldApprovalCancelled: XCTestExpectation) {
            self.oldApprovalReached = oldApprovalReached
            self.oldApprovalCancelled = oldApprovalCancelled
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }

        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt {
            approvalCalls += 1
            if approvalCalls == 1 {
                oldApprovalReached.fulfill()
                await oldApprovalGate.wait()
                if Task.isCancelled { oldApprovalCancelled.fulfill() }
                throw DSHTransportError.invalidEndpoint
            }
            return .init(accepted: true, reason: nil)
        }

        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class DelayedReplayedQuestionSessionAPI: NativeSessionAPI {
        let oldAnswerReached: XCTestExpectation
        let oldAnswerCancelled: XCTestExpectation
        private let oldAnswerGate = RecoveryGate()
        private(set) var answerCalls = 0

        init(oldAnswerReached: XCTestExpectation, oldAnswerCancelled: XCTestExpectation) {
            self.oldAnswerReached = oldAnswerReached
            self.oldAnswerCancelled = oldAnswerCancelled
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }

        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt {
            answerCalls += 1
            if answerCalls == 1 {
                oldAnswerReached.fulfill()
                await oldAnswerGate.wait()
                if Task.isCancelled { oldAnswerCancelled.fulfill() }
                throw DSHTransportError.invalidEndpoint
            }
            return .init(accepted: true, reason: nil)
        }

        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }

        func failOldAnswer() async {
            await oldAnswerGate.open()
        }
    }

    @MainActor
    private final class DelayedOpeningHistorySessionAPI: NativeSessionAPI {
        let staleHistoryReached: XCTestExpectation
        private let historyGate = RecoveryGate()
        private let failStaleHistory: Bool
        private(set) var historyCalls = 0
        private var modelsCalls = 0

        init(staleHistoryReached: XCTestExpectation, failStaleHistory: Bool = false) {
            self.staleHistoryReached = staleHistoryReached
            self.failStaleHistory = failStaleHistory
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCalls += 1
            if historyCalls == 1 {
                staleHistoryReached.fulfill()
                await historyGate.wait()
                if failStaleHistory { throw DSHTransportError.invalidEndpoint }
                return .init(events: [historyEntry(seq: 1, id: "stale", text: "stale authority")], hasMore: false, projections: nil)
            }
            return .init(events: [historyEntry(seq: 2, id: "resynced", text: "resynced authority")], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            modelsCalls += 1
            return .init(
                current: .init(provider: "provider", model: modelsCalls == 1 ? "stale-model" : "resynced-model", reasoningEffort: nil),
                routable: true,
                groups: [],
                failures: []
            )
        }

        func releaseHistory() async { await historyGate.open() }
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
    private final class FixedOpeningSessionAPI: NativeSessionAPI {
        let model: String
        let text: String

        init(model: String, text: String) {
            self.model = model
            self.text = text
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [.init(event: .init(
                type: "user/message",
                seq: 1,
                time: 1,
                data: .object([
                    "id": .string("fresh"),
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: .string("append"),
                sourceEventSeqs: nil,
                ignorable: nil
            ), view: nil)], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: model, reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class CoalescingGapFailureSessionAPI: NativeSessionAPI {
        let recoveryHistoryReached: XCTestExpectation
        private let failureGate = RecoveryGate()
        private(set) var historyCalls = 0

        init(recoveryHistoryReached: XCTestExpectation) {
            self.recoveryHistoryReached = recoveryHistoryReached
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            historyCalls += 1
            if historyCalls == 1 {
                return .init(events: [historyEntry(seq: 1, id: "baseline", text: "baseline")], hasMore: false, projections: nil)
            }
            recoveryHistoryReached.fulfill()
            await failureGate.wait()
            throw DSHTransportError.invalidEndpoint
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
        }

        func failRecovery() async { await failureGate.open() }
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
    private final class PromptRouteSessionAPI: NativeSessionAPI {
        var routable = false
        private(set) var promptContents: [[SessionPromptContent]] = []

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
            .init(events: [], hasMore: false, projections: nil)
        }

        func models(sessionID _: String) async throws -> SessionModelsResponse {
            .init(
                current: .init(provider: "provider", model: "model", reasoningEffort: nil),
                routable: routable,
                groups: [.init(id: "provider", name: "Provider", models: [
                    .init(id: "model", name: "Model", description: nil, reasoning: nil),
                ])],
                failures: []
            )
        }

        func prompt(sessionID _: String, content: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse {
            promptContents.append(content)
            return .init(accepted: true)
        }
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
        let opensAuthority: Bool
        let imageLimits: ImageAttachmentLimits?
        private(set) var prompts: [Prompt] = []
        private(set) var cancelledSessionIDs: [String] = []

        init(
            promptReachedFacade: XCTestExpectation?,
            cancelReachedFacade: XCTestExpectation? = nil,
            opensAuthority: Bool = false,
            imageLimits: ImageAttachmentLimits? = nil
        ) {
            self.promptReachedFacade = promptReachedFacade
            self.cancelReachedFacade = cancelReachedFacade
            self.opensAuthority = opensAuthority
            self.imageLimits = imageLimits
        }

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws {
            guard opensAuthority else { throw DSHTransportError.invalidEndpoint }
            let projections = imageLimits.map {
                SessionProjectionsDTO(asOfSeq: 0, values: [
                    "imageLimits": .object([
                        "maxImageBytes": .number(Double($0.maxImageBytes)),
                        "maxImagesPerMessage": .number(Double($0.maxImagesPerMessage)),
                        "maxMessageImageBytes": .number(Double($0.maxMessageImageBytes)),
                        "maxImagePixels": .number(Double($0.maxImagePixels)),
                        "maxImageDimension": .number(Double($0.maxImageDimension)),
                        "mediaTypes": .array($0.mediaTypes.map(JSONValue.string)),
                    ]),
                ])
            }
            return .init(events: [], hasMore: false, projections: projections)
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
            guard opensAuthority else { throw DSHTransportError.invalidEndpoint }
            return .init(current: .init(provider: "provider", model: "model", reasoningEffort: nil), routable: true, groups: [], failures: [])
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
