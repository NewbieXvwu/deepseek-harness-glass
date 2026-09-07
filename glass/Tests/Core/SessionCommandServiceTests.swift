import XCTest

@testable import GlassCore

final class SessionCommandServiceTests: XCTestCase {
    private struct MockError: Error {}

    private final actor MockSessionController: SessionControllerAPI {
        private(set) var promptRequests: [RemoteSessionPromptRequest] = []
        private var promptFailuresRemaining = 0

        func failNextPrompts(_ count: Int) {
            promptFailuresRemaining = count
        }

        func prompt(_ request: RemoteSessionPromptRequest) async throws -> RemoteSessionAcceptedValue {
            promptRequests.append(request)
            if promptFailuresRemaining > 0 {
                promptFailuresRemaining -= 1
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

    func testPromptIntentOwnsExactRequestPayload() {
        let controller = MockSessionController()
        let service = SessionCommandService(controller: controller)
        let content: [RemotePromptContentPart] = [
            .text("hello"),
            .image(mediaType: "image/png", data: "AA==", name: "a.png"),
        ]

        let intent = service.makePromptIntent(
            sessionID: "s1",
            mode: .queue,
            content: content,
            clientTimeZone: "Asia/Shanghai"
        )

        XCTAssertEqual(intent.sessionID, "s1")
        XCTAssertEqual(intent.mode, .queue)
        XCTAssertEqual(intent.content, content)
        XCTAssertEqual(intent.clientTimeZone, "Asia/Shanghai")
        XCTAssertEqual(intent.request.requestId, intent.requestID)
        XCTAssertEqual(intent.request.sessionId, "s1")
        XCTAssertEqual(intent.request.content, content)
    }

    func testRetryReusesRequestIDAndExactPayload() async throws {
        let controller = MockSessionController()
        await controller.failNextPrompts(1)
        let service = SessionCommandService(controller: controller)
        let intent = service.makePromptIntent(
            sessionID: "s1",
            mode: .queue,
            content: [.text("retry me")],
            clientTimeZone: "UTC"
        )

        do {
            try await service.submitPrompt(intent)
            XCTFail("first submission should fail")
        } catch is MockError {
            // Expected transport failure; the intent remains reusable.
        }
        try await service.retryPrompt(intent)

        let requests = await controller.promptRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0], intent.request)
        XCTAssertEqual(requests[1], intent.request)
        XCTAssertEqual(requests[0].requestId, requests[1].requestId)
    }

    func testNewUserIntentGetsFreshIdentity() {
        let controller = MockSessionController()
        let service = SessionCommandService(controller: controller)

        let first = service.makePromptIntent(sessionID: "s1", mode: .queue, content: [.text("first")])
        let second = service.makePromptIntent(sessionID: "s1", mode: .queue, content: [.text("second")])

        XCTAssertNotEqual(first.requestID, second.requestID)
        XCTAssertNotEqual(first.content, second.content)
    }
}
