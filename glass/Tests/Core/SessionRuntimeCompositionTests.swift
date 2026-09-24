import XCTest

@testable import GlassCore

final class SessionRuntimeCompositionTests: XCTestCase {
    private struct MockError: Error {}
    private typealias FollowProvider = @Sendable () throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error>
    private typealias ControlProvider = @Sendable () throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error>

    private final actor MockController: SessionControllerAPI {
        private var followProviders: [FollowProvider] = []
        private var controlProviders: [ControlProvider] = []
        private var pages: [RemoteSessionPageValue] = []
        private(set) var followRequests: [RemoteSessionFollowRequest] = []
        private(set) var pageRequests: [RemoteSessionPageRequest] = []

        func queueFollow(_ provider: @escaping FollowProvider) { followProviders.append(provider) }
        func queueControl(_ provider: @escaping ControlProvider) { controlProviders.append(provider) }
        func queuePage(_ page: RemoteSessionPageValue) { pages.append(page) }

        func follow(_ request: RemoteSessionFollowRequest) async throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error> {
            followRequests.append(request)
            guard !followProviders.isEmpty else { throw MockError() }
            return try followProviders.removeFirst()()
        }

        func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error> {
            guard !controlProviders.isEmpty else { throw MockError() }
            return try controlProviders.removeFirst()()
        }

        func page(_ request: RemoteSessionPageRequest) async throws -> RemoteSessionPageValue {
            pageRequests.append(request)
            guard !pages.isEmpty else { throw MockError() }
            return pages.removeFirst()
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
        func prompt(_ request: RemoteSessionPromptRequest) async throws -> RemoteSessionAcceptedValue { fatalError() }
        func attachment(sessionID: String, attachmentID: String) async throws -> RemoteSessionAttachmentValue { fatalError() }
        func cancel(sessionID: String) async throws -> RemoteSessionAcceptedValue { fatalError() }
        func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws -> RemoteSessionAcceptedValue { fatalError() }
    }

    func testAggregateStateCombinesAddressedJournalAndCurrentGenerationControl() async throws {
        let controller = MockController()
        await controller.queueControl {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(.baseline(.init(
                queues: [
                    "s1": [Self.queue(id: "q1")],
                    "s2": [Self.queue(id: "other")],
                ],
                jobs: [
                    "s1": [Self.job(id: "j1")],
                    "s2": [],
                ],
                projections: [
                    "s1": .init(asOfSeq: .init(rawValue: 1), values: ["model": .string("m1")]),
                ]
            )))
            return stream
        }
        await controller.queueFollow {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.opening(sessionID: "s1", cursor: 1, hasMore: false))
            return stream
        }

        let generation = RemoteConnectionGeneration(rawValue: 21)
        let control = SessionControlRuntime(controller: controller, generation: generation)
        _ = try await control.open()
        let runtime = SessionRuntime(
            controller: controller,
            generation: generation,
            address: .session(sessionID: "s1"),
            controlRuntime: control
        )
        _ = try await runtime.open()

        let state = try await eventuallyState(runtime) { $0.control?.queue.first?.id == "q1" }
        XCTAssertEqual(state.journal.address, .session(sessionID: "s1"))
        XCTAssertEqual(state.control?.generation, generation)
        XCTAssertEqual(state.control?.queue.map(\.id), ["q1"])
        XCTAssertEqual(state.control?.jobs.map(\.id), ["j1"])
        XCTAssertEqual(state.control?.projections?.values["model"], .string("m1"))

        await control.invalidate()
        let invalidated = try await eventuallyState(runtime) { $0.control == nil }
        XCTAssertNil(invalidated.control)
        XCTAssertEqual(invalidated.journal.appliedThrough, SessionSeq(rawValue: 1))
        await runtime.close()
    }

    func testDirectSubagentAddressDrivesFollowPageAndChildControlSelection() async throws {
        let controller = MockController()
        let address = SessionAddress.subagent(
            parentSessionID: "parent",
            childSessionID: "child",
            mode: .continuable
        )
        await controller.queueControl {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(.baseline(.init(
                queues: [
                    "parent": [Self.queue(id: "parent-q")],
                    "child": [Self.queue(id: "child-q")],
                ],
                jobs: ["child": [Self.job(id: "child-j")]],
                projections: [:]
            )))
            return stream
        }
        await controller.queueFollow {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.opening(sessionID: "child", cursor: 2, hasMore: true))
            return stream
        }
        await controller.queuePage(.init(records: [Self.record(sessionID: "child", seq: 1)], hasMore: false))

        let generation = RemoteConnectionGeneration(rawValue: 22)
        let control = SessionControlRuntime(controller: controller, generation: generation)
        _ = try await control.open()
        let runtime = SessionRuntime(
            controller: controller,
            generation: generation,
            address: address,
            maxMessages: 50,
            controlRuntime: control
        )

        _ = try await runtime.open()
        _ = try await runtime.loadOlder(maxMessages: 25)
        let state = try await eventuallyState(runtime) { $0.control?.queue.first?.id == "child-q" }
        XCTAssertEqual(state.journal.records.map(\.firstSeq), [
            SessionSeq(rawValue: 1), SessionSeq(rawValue: 2),
        ])
        XCTAssertEqual(state.control?.queue.map(\.id), ["child-q"])
        XCTAssertEqual(state.control?.jobs.map(\.id), ["child-j"])

        let follows = await controller.followRequests
        XCTAssertEqual(follows, [.init(address: address, maxMessages: 50)])
        let pages = await controller.pageRequests
        XCTAssertEqual(pages, [.init(
            address: address,
            throughSeq: SessionSeq(rawValue: 2),
            beforeSeq: SessionLogOffset(rawValue: 2),
            maxMessages: 25
        )])
        await runtime.close()
        await control.invalidate()
    }

    private func eventuallyState(
        _ runtime: SessionRuntime,
        predicate: (SessionRuntimeState) -> Bool
    ) async throws -> SessionRuntimeState {
        for _ in 0..<200 {
            if let state = await runtime.currentState(), predicate(state) { return state }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw MockError()
    }

    private static func opening(sessionID: String, cursor: Int, hasMore: Bool) -> RemoteSessionFollowFrame {
        .snapshot(
            header: .init(
                version: 1,
                id: sessionID,
                createdAt: 1,
                cwd: "/tmp",
                parentSession: nil,
                seedLength: nil,
                origin: nil,
                delegationDepth: nil,
                agentPreset: nil
            ),
            cursor: .init(rawValue: cursor),
            records: [record(sessionID: sessionID, seq: cursor)],
            hasMore: hasMore,
            projections: .init(asOfSeq: .init(rawValue: cursor), values: [:])
        )
    }

    private static func record(sessionID: String, seq: Int) -> RemoteSessionHistoryRecord {
        .event(.init(
            type: "user/message",
            seq: .init(rawValue: seq),
            time: Int64(seq),
            data: .object([
                "session": .string(sessionID),
                "content": .string("event-\(seq)"),
            ]),
            ignorable: false,
            sourceEventSeqs: nil,
            surfaceOp: .string("append")
        ))
    }

    private static func queue(id: String) -> RemoteSessionQueuedItem {
        .init(
            id: id,
            placement: .queued,
            rpcId: nil,
            message: .init(id: "message-\(id)", content: [.string(id)])
        )
    }

    private static func job(id: String) -> RemoteSessionJob {
        .init(
            id: id,
            kind: "bash",
            label: id,
            status: .running,
            detail: nil,
            startedAt: 1,
            finishedAt: nil
        )
    }
}
