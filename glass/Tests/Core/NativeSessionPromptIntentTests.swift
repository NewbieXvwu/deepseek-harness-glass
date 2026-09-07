import XCTest

@testable import GlassCore

@MainActor
final class NativeSessionPromptIntentTests: XCTestCase {
    private struct MockError: Error {}

    private final actor PromptController: SessionControllerAPI {
        private(set) var requests: [RemoteSessionPromptRequest] = []
        private var failuresRemaining: Int

        init(failuresRemaining: Int) {
            self.failuresRemaining = failuresRemaining
        }

        func prompt(_ request: RemoteSessionPromptRequest) async throws -> RemoteSessionAcceptedValue {
            requests.append(request)
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw MockError()
            }
            return .init(accepted: true)
        }

        func list() async throws -> RemoteSessionListValue { fatalError() }
        func search(query: String) async throws -> RemoteSessionSearchValue { fatalError() }
        func create(_ request: RemoteSessionCreateRequest) async throws -> RemoteSessionCreateValue { fatalError() }
        func rename(sessionID: String, title: String) async throws -> RemoteSessionRenameValue { fatalError() }
        func fork(sessionID: String, atSeq: SessionSeq?) async throws -> RemoteSessionForkValue { fatalError() }
        func selectModel(sessionID: String, selection: RemoteModelSelection) async throws -> RemoteSessionSelectModelValue { fatalError() }
        func modelCatalog() async throws -> RemoteModelCatalog { fatalError() }
        func canOpenWorkspacePath() async throws -> Bool { false }
        func openWorkspacePath(_ path: String) async throws -> RemoteSessionOpenWorkspacePathValue { fatalError() }
        func attachment(sessionID: String, attachmentID: String) async throws -> RemoteSessionAttachmentValue { fatalError() }
        func cancel(sessionID: String) async throws -> RemoteSessionAcceptedValue { fatalError() }
        func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws -> RemoteSessionAcceptedValue { fatalError() }
        func page(_ request: RemoteSessionPageRequest) async throws -> RemoteSessionPageValue { fatalError() }
        func follow(_ request: RemoteSessionFollowRequest) async throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error> { fatalError() }
        func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error> { fatalError() }
    }

    func testFailedComposerRetryReusesSamePromptIdentityAndPayload() async throws {
        let controller = PromptController(failuresRemaining: 1)
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.bindCommandService(SessionCommandService(controller: controller))
        store.draft = "retry this exact intent"

        store.submitDraft()
        try await waitUntil { !store.isSubmittingPrompt && store.pendingPromptIntent != nil }
        let retained = try XCTUnwrap(store.pendingPromptIntent)
        XCTAssertEqual(store.draft, "retry this exact intent")

        store.submitDraft()
        try await waitUntil { !store.isSubmittingPrompt && store.pendingPromptIntent == nil }

        let requests = await controller.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0], requests[1])
        XCTAssertEqual(requests[0].requestId, retained.requestID)
        XCTAssertTrue(store.draft.isEmpty)
    }

    func testEditingComposerAfterFailureCreatesFreshPromptIdentity() async throws {
        let controller = PromptController(failuresRemaining: 1)
        let store = NativeSessionStore()
        store.loadSnapshotToolingFixture()
        store.bindCommandService(SessionCommandService(controller: controller))
        store.draft = "first payload"

        store.submitDraft()
        try await waitUntil { !store.isSubmittingPrompt && store.pendingPromptIntent != nil }
        let firstIntent = try XCTUnwrap(store.pendingPromptIntent)

        store.draft = "edited payload"
        store.submitDraft()
        try await waitUntil { !store.isSubmittingPrompt && store.pendingPromptIntent == nil }

        let requests = await controller.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].requestId, firstIntent.requestID)
        XCTAssertNotEqual(requests[0].requestId, requests[1].requestId)
        XCTAssertNotEqual(requests[0].content, requests[1].content)
        XCTAssertTrue(store.draft.isEmpty)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !predicate() {
            if ContinuousClock.now - start > .nanoseconds(Int64(timeoutNanoseconds)) {
                throw MockError()
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
