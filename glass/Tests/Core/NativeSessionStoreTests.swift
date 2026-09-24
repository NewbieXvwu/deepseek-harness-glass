import XCTest
import GlassSpec
@testable import GlassPortableCore
@testable import GlassCore

@MainActor
private extension NativeSessionStore {
    func open(
        sessionID: String,
        using api: any NativeSessionAPI,
        endpoint: URL,
        hostPathAPI: (any NativeHostPathAPI)? = nil,
        goalAPI: (any NativeGoalAPI)? = nil,
        subagentCatalogAPI: (any NativeSubagentCatalogAPI)? = nil,
        subagentContinuationAPI: (any NativeSubagentContinuationAPI)? = nil,
        messageFeedbackAPI: (any NativeMessageFeedbackAPI)? = nil,
        sessionCWD: String? = nil,
        sessionRuntime: SessionRuntime? = nil
    ) {
        setSessionAPIForTesting(api)
        open(
            sessionID: sessionID,
            endpoint: endpoint,
            hostPathAPI: hostPathAPI,
            goalAPI: goalAPI,
            subagentCatalogAPI: subagentCatalogAPI,
            subagentContinuationAPI: subagentContinuationAPI,
            messageFeedbackAPI: messageFeedbackAPI,
            sessionCWD: sessionCWD,
            sessionRuntime: sessionRuntime
        )
    }
}

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
        store.projections.apply(
    sessionID: "rejected-image-prompt-session",
    key: "imageLimits",
    value: .object([
        "maxImageBytes": .number(4_096),
        "maxImagesPerMessage": .number(2),
        "maxMessageImageBytes": .number(8_192),
        "maxImagePixels": .number(16),
        "maxImageDimension": .number(4),
        "mediaTypes": .array([.string("image/png")]),
    ]),
    seq: 0
)
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
        store.projections.apply(
    sessionID: sessionID,
    key: "imageLimits",
    value: .object([
        "maxImageBytes": .number(4_096),
        "maxImagesPerMessage": .number(2),
        "maxMessageImageBytes": .number(8_192),
        "maxImagePixels": .number(16),
        "maxImageDimension": .number(4),
        "mediaTypes": .array([.string("image/png")]),
    ]),
    seq: 0
)
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

    func testPermissionProjectionAndCommandSelectionStayHostAuthoritative() async throws {
        let submitted = expectation(description: "permission command reaches session facade")
        let api = PermissionCommandSessionAPI(submitted: submitted)
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let sessionID = try tryUnwrap(store.selectedSessionID)
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

    func testSessionSwitchCancelsPendingPermissionCommandBeforeLateAcceptanceCanAffectNewSession() async throws {
        let commandReached = expectation(description: "permission command reaches Host before session switch")
        let commandCancelled = expectation(description: "permission command Task cancels on session switch")
        let api = DelayedPromptSessionAPI(oldPromptReached: commandReached, oldPromptCancelled: commandCancelled)
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let oldSessionID = try tryUnwrap(store.selectedSessionID)
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
        XCTAssertTrue(store.chatNodes.isEmpty)
        XCTAssertNil(store.modelDirectory)
        XCTAssertNil(store.extensionState?.modelDirectory)
        XCTAssertTrue(store.extensionState?.queuedMessages.isEmpty == true)
        XCTAssertTrue(store.extensionState?.backgroundJobs.isEmpty == true)
    }


    func testClearActiveSelectionRetainsResidentSessionForLaterReopen() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        let originalNodeKeys = store.chatNodes.map(\.key)
        XCTAssertEqual(store.selectedSessionID, "snapshot-tooling")

        store.clearActiveSelection()

        XCTAssertNil(store.selectedSessionID)
        XCTAssertTrue(store.chatNodes.isEmpty)
        XCTAssertNil(store.modelDirectory)
        XCTAssertNil(store.extensionState)
        XCTAssertTrue(store.restoreResidentState(for: "snapshot-tooling"))
        XCTAssertEqual(store.chatNodes.map(\.key), originalNodeKeys)
    }





















    func testSessionModelsAuthorityPublishesTypedDirectoryAndClearsForColdSession() async throws {
        let modelsLoaded = expectation(description: "session.models reaches typed facade")
        let api = ModelDirectorySessionAPI(modelsLoaded: modelsLoaded)
        let store = NativeSessionStore()
        store.open(sessionID: "models-session", using: api, endpoint: URL(string: "http://127.0.0.1:1")!)
        await fulfillment(of: [modelsLoaded], timeout: 1)
        await eventually(timeout: 1) { store.modelDirectory != nil }

        let directory = try tryUnwrap(store.modelDirectory)
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

    func testToolingFixtureMaterializesTrajectoryTargetSeparatelyFromChat() {
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()

        XCTAssertEqual(store.chatNodes.map(\.target), ["chat", "chat"])
        XCTAssertEqual(store.trajectoryNodes.map(\.target), ["trajectory"])
        XCTAssertEqual(store.trajectoryNodes.map(\.kind), ["trajectory-input-message"])
        XCTAssertEqual((store.trajectoryNodes.first?.data as? CoreUserMessageNode)?.content.compactMap(\.text).joined(), "Read the project instructions.")
    }

    func testGoalActionsUseActiveHostProjectionRefWithoutOptimisticMutation() async throws {
        let store = NativeSessionStore()
        store.loadSnapshotTodoFixture()
        let sessionID = try tryUnwrap(store.selectedSessionID)
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

    func testSuccessfulGoalClearUsesPresentationMarkerWithoutMutatingProjection() async throws {
        let store = NativeSessionStore()
        store.loadSnapshotTodoFixture()
        let sessionID = try tryUnwrap(store.selectedSessionID)
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

    func testGoalActionSurfacesOnlyHostBusinessFailureAndKeepsProjection() async throws {
        let store = NativeSessionStore()
        store.loadSnapshotTodoFixture()
        let sessionID = try tryUnwrap(store.selectedSessionID)
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

    func testQueueActionFailureIsScopedToItsItemAndSuccessPublishesCompletion() async {
        let store = NativeSessionStore()
        store.loadSnapshotQueueFixture()
        let api = RecordingQueueActionAPI()
        store.setSessionAPIForTesting(api)

        api.error = .init(code: "queue_conflict", message: "no longer queued", details: .object([:]))
        store.updateQueuedMessage(itemID: "snapshot-queue-text", action: .remove)
        await eventually(timeout: 1) { store.queueActionFailure != nil && store.updatingQueueItemID == nil }

        XCTAssertEqual(store.queueActionFailure, .init(itemID: "snapshot-queue-text", kind: .remove))
        XCTAssertNil(store.queueActionCompletion)

        api.error = nil
        store.updateQueuedMessage(itemID: "snapshot-queue-image", action: .steer)
        await eventually(timeout: 1) { store.queueActionCompletion != nil && store.updatingQueueItemID == nil }

        XCTAssertEqual(store.queueActionCompletion, .init(itemID: "snapshot-queue-image", action: .steer))
        XCTAssertNil(store.queueActionFailure)
        XCTAssertEqual(api.requests, [
            .init(sessionId: "snapshot-tooling", itemId: "snapshot-queue-text", action: .remove),
            .init(sessionId: "snapshot-tooling", itemId: "snapshot-queue-image", action: .steer),
        ])
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



























    @MainActor
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

    @MainActor
    private func eventually(timeout: TimeInterval, condition: () -> Bool) async {
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
    private final class DelayedPromptSessionAPI: NativeSessionAPI {
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            throw DSHTransportError.invalidEndpoint
        }

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
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            throw DSHTransportError.invalidEndpoint
        }

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
    private final class RecordingQueueActionAPI: NativeSessionAPI {
        var error: RPCBusinessError?
        private(set) var requests: [SessionUpdateQueueRequest] = []

        func updateQueue(_ request: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            requests.append(request)
            if let error { throw error }
            return .init(accepted: true)
        }

        func prompt(sessionID _: String, content _: [SessionPromptContent], mode _: SessionPromptMode) async throws -> SessionPromptResponse { throw DSHTransportError.invalidEndpoint }
        func cancel(sessionID _: String) async throws -> SessionCancelResponse { throw DSHTransportError.invalidEndpoint }
        func models(sessionID _: String) async throws -> SessionModelsResponse { throw DSHTransportError.invalidEndpoint }
        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse { throw DSHTransportError.invalidEndpoint }
        func answerApproval(rpcID _: String, sessionID _: String, approvalID _: String, outcome _: ApprovalOutcome) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func answerQuestion(rpcID _: String, sessionID _: String, answers _: [QuestionAnswerResponse]) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
        func cancelQuestion(rpcID _: String) async throws -> RPCReceipt { throw DSHTransportError.invalidEndpoint }
    }

    @MainActor
    private final class GatedInitialModelsAPI: NativeSessionAPI {
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            throw DSHTransportError.invalidEndpoint
        }

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
    private final class ModelDirectorySessionAPI: NativeSessionAPI {
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            throw DSHTransportError.invalidEndpoint
        }

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
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            throw DSHTransportError.invalidEndpoint
        }

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
    private final class PromptRouteSessionAPI: NativeSessionAPI {
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            throw DSHTransportError.invalidEndpoint
        }

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
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

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
        func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
            throw DSHTransportError.invalidEndpoint
        }

        func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
            throw DSHTransportError.invalidEndpoint
        }

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

        func history(sessionID _: String, beforeSeq _: Int?, maxMessages _: Int?) async throws -> SessionHistoryResponse {
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

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try XCTUnwrap(value, "Expected non-nil value", file: file, line: line)
    }

}
