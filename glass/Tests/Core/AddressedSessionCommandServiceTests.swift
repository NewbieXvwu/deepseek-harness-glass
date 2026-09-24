import XCTest

@testable import GlassCore

final class AddressedSessionCommandServiceTests: XCTestCase {
    private final actor SessionControllerMock: SessionControllerAPI {
        private(set) var prompts: [RemoteSessionPromptRequest] = []
        private(set) var cancellations: [String] = []

        func prompt(_ request: RemoteSessionPromptRequest) async throws -> RemoteSessionAcceptedValue {
            prompts.append(request)
            return .init(accepted: true)
        }

        func cancel(sessionID: String) async throws -> RemoteSessionAcceptedValue {
            cancellations.append(sessionID)
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
        func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws -> RemoteSessionAcceptedValue { fatalError() }
        func page(_ request: RemoteSessionPageRequest) async throws -> RemoteSessionPageValue { fatalError() }
        func follow(_ request: RemoteSessionFollowRequest) async throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error> { fatalError() }
        func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error> { fatalError() }
    }

    private final actor SubagentControllerMock: SubagentControllerAPI {
        private(set) var prompts: [RemoteSubagentPromptRequest] = []
        private(set) var interrupts: [(parent: String, child: String)] = []

        func list(parentSessionID: String) async throws -> RemoteSubagentCatalog { fatalError() }

        func prompt(_ request: RemoteSubagentPromptRequest) async throws -> RemoteSubagentPromptReceipt {
            prompts.append(request)
            return .init(messageId: "accepted-message")
        }

        func interrupt(parentSessionID: String, childSessionID: String) async throws -> RemoteSubagentInterruptReceipt {
            interrupts.append((parentSessionID, childSessionID))
            return .init(accepted: true)
        }
    }

    func testOrdinaryAddressRoutesPromptAndCancelOnlyToSessionController() async throws {
        let sessions = SessionControllerMock()
        let subagents = SubagentControllerMock()
        let service = AddressedSessionCommandService(
            address: .session(sessionID: "ordinary"),
            controller: sessions,
            subagents: subagents
        )
        let intent = try service.makePromptIntent(mode: .queue, content: [.text("hello")])

        try await service.submitPrompt(intent)
        try await service.cancel()

        let sessionPrompts = await sessions.prompts
        let sessionCancellations = await sessions.cancellations
        let childPrompts = await subagents.prompts
        let childInterrupts = await subagents.interrupts
        XCTAssertEqual(sessionPrompts.count, 1)
        XCTAssertEqual(sessionPrompts.first?.sessionId, "ordinary")
        XCTAssertEqual(sessionCancellations, ["ordinary"])
        XCTAssertTrue(childPrompts.isEmpty)
        XCTAssertTrue(childInterrupts.isEmpty)
    }

    func testContinuableAddressRoutesPromptRetryAndStopToSubagentOwner() async throws {
        let sessions = SessionControllerMock()
        let subagents = SubagentControllerMock()
        let service = AddressedSessionCommandService(
            address: .subagent(
                parentSessionID: "parent",
                childSessionID: "child",
                mode: .continuable
            ),
            controller: sessions,
            subagents: subagents
        )
        let intent = try service.makePromptIntent(
            mode: .queue,
            content: [.text("continue")],
            clientTimeZone: "UTC"
        )

        try await service.submitPrompt(intent)
        try await service.retryPrompt(intent)
        try await service.cancel()

        let childPrompts = await subagents.prompts
        let childInterrupts = await subagents.interrupts
        let sessionPrompts = await sessions.prompts
        let sessionCancellations = await sessions.cancellations
        XCTAssertEqual(childPrompts.count, 2)
        XCTAssertEqual(childPrompts[0], childPrompts[1])
        XCTAssertEqual(childPrompts[0].parentSessionId, "parent")
        XCTAssertEqual(childPrompts[0].childSessionId, "child")
        XCTAssertEqual(childPrompts[0].requestId, intent.requestID)
        XCTAssertEqual(childInterrupts.count, 1)
        XCTAssertEqual(childInterrupts.first?.parent, "parent")
        XCTAssertEqual(childInterrupts.first?.child, "child")
        XCTAssertTrue(sessionPrompts.isEmpty)
        XCTAssertTrue(sessionCancellations.isEmpty)
    }

    func testContinuableAddressRejectsOrdinarySteerMode() {
        let service = AddressedSessionCommandService(
            address: .subagent(parentSessionID: "parent", childSessionID: "child", mode: .continuable),
            controller: SessionControllerMock(),
            subagents: SubagentControllerMock()
        )

        XCTAssertThrowsError(try service.makePromptIntent(mode: .steer, content: [.text("steer")])) { error in
            XCTAssertEqual(
                error as? AddressedSessionCommandError,
                .unsupportedSubagentPromptMode(.steer)
            )
        }
    }

    func testOneShotAddressIsReadOnlyAtCommandBoundary() async {
        let service = AddressedSessionCommandService(
            address: .subagent(parentSessionID: "parent", childSessionID: "child", mode: .oneShot),
            controller: SessionControllerMock(),
            subagents: SubagentControllerMock()
        )

        XCTAssertThrowsError(try service.makePromptIntent(mode: .queue, content: [.text("forbidden")])) { error in
            XCTAssertEqual(error as? AddressedSessionCommandError, .oneShotReadOnly)
        }
        do {
            try await service.cancel()
            XCTFail("one-shot child must remain read-only")
        } catch let error as AddressedSessionCommandError {
            XCTAssertEqual(error, .oneShotReadOnly)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSubagentQueueAndModelMutationsFailClosedInsteadOfCallingSessionEndpoint() async {
        let sessions = SessionControllerMock()
        let service = AddressedSessionCommandService(
            address: .subagent(parentSessionID: "parent", childSessionID: "child", mode: .continuable),
            controller: sessions,
            subagents: SubagentControllerMock()
        )

        do {
            try await service.updateQueue(itemID: "q", action: .remove)
            XCTFail("subagent queue mutation has no rc.1 addressed command")
        } catch let error as AddressedSessionCommandError {
            XCTAssertEqual(error, .unsupportedSubagentCommand)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let sessionPrompts = await sessions.prompts
        let sessionCancellations = await sessions.cancellations
        XCTAssertTrue(sessionPrompts.isEmpty)
        XCTAssertTrue(sessionCancellations.isEmpty)
    }
}
