import Foundation
import XCTest

@testable import GlassCore

final class SessionRuntimeResilienceTests: XCTestCase {
    private struct MockError: Error, Equatable {}

    private typealias StreamProvider = @Sendable () throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error>

    private final actor MockSessionController: SessionControllerAPI {
        private var followStreams: [StreamProvider] = []
        private(set) var followCallCount = 0

        func queueFollowStream(_ provider: @escaping StreamProvider) {
            followStreams.append(provider)
        }

        func follow(_ request: RemoteSessionFollowRequest) async throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error> {
            followCallCount += 1
            let provider = followStreams.isEmpty ? nil : followStreams.removeFirst()

            guard let provider else {
                throw MockError()
            }
            return try provider()
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
        func cancel(sessionID: String) async throws -> RemoteSessionAcceptedValue { fatalError() }
        func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws -> RemoteSessionAcceptedValue { fatalError() }
        func page(_ request: RemoteSessionPageRequest) async throws -> RemoteSessionPageValue { fatalError() }
        func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error> { fatalError() }
    }

    private static func makeOpeningSnapshot(sessionID: String = "test-session", cursor: Int = 1) -> RemoteSessionFollowFrame {
        .snapshot(
            header: RemoteSessionWireHeader(
                version: 1,
                id: sessionID,
                createdAt: 1000,
                cwd: "/test",
                parentSession: nil,
                seedLength: nil,
                origin: nil,
                delegationDepth: nil,
                agentPreset: nil
            ),
            cursor: SessionSeq(rawValue: cursor),
            records: [
                .event(RemoteSessionWireEvent(
                    type: "user/message",
                    seq: SessionSeq(rawValue: cursor),
                    time: 1000,
                    data: .object(["content": .string("hello")]),
                    ignorable: false,
                    sourceEventSeqs: nil,
                    surfaceOp: .string("append")
                ))
            ],
            hasMore: false,
            projections: RemoteSessionProjectionBaseline(
                asOfSeq: SessionSeq(rawValue: cursor),
                values: [:]
            )
        )
    }

    private static func makeEventFrame(seq: Int) -> RemoteSessionFollowFrame {
        .event(RemoteSessionWireEvent(
            type: "assistant/message",
            seq: SessionSeq(rawValue: seq),
            time: 1000 + Int64(seq),
            data: .object(["content": .string("reply \(seq)")]),
            ignorable: false,
            sourceEventSeqs: nil,
            surfaceOp: .string("append")
        ))
    }

    func testInitialHandshakeFailurePropagatesImmediatelyWithoutHanging() async throws {
        let mockController = MockSessionController()
        await mockController.queueFollowStream {
            throw MockError()
        }

        let runtime = SessionRuntime(
            controller: mockController,
            generation: RemoteConnectionGeneration(rawValue: 1),
            address: .session(sessionID: "test-session")
        )

        do {
            _ = try await runtime.open()
            XCTFail("首帧握手失败必须立即抛错，严禁假死！")
        } catch is MockError {
            // Expected
        }
        let calls = await mockController.followCallCount
        XCTAssertEqual(calls, 1)
    }

    func testNormalStreamEndDoesNotReplayFollowWithinSameGeneration() async throws {
        let mockController = MockSessionController()

        await mockController.queueFollowStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.makeOpeningSnapshot(sessionID: "test-session", cursor: 1))
            continuation.finish()
            return stream
        }
        await mockController.queueFollowStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.makeOpeningSnapshot(sessionID: "test-session", cursor: 2))
            return stream
        }

        let runtime = SessionRuntime(
            controller: mockController,
            generation: RemoteConnectionGeneration(rawValue: 1),
            address: .session(sessionID: "test-session")
        )

        _ = try await runtime.open()
        try await Task.sleep(nanoseconds: 100_000_000)
        let followCallCount = await mockController.followCallCount
        XCTAssertEqual(followCallCount, 1)
        await runtime.close()
    }

    func testLiveGapPerformsOneAuthoritativeContinuityResync() async throws {
        let mockController = MockSessionController()

        await mockController.queueFollowStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.makeOpeningSnapshot(sessionID: "test-session", cursor: 1))
            continuation.yield(Self.makeEventFrame(seq: 3))
            return stream
        }
        await mockController.queueFollowStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.makeOpeningSnapshot(sessionID: "test-session", cursor: 3))
            return stream
        }

        let runtime = SessionRuntime(
            controller: mockController,
            generation: RemoteConnectionGeneration(rawValue: 1),
            address: .session(sessionID: "test-session")
        )

        _ = try await runtime.open()
        for _ in 0..<100 {
            if await mockController.followCallCount == 2,
               await runtime.currentSnapshot()?.openingCut == SessionSeq(rawValue: 3) {
                await runtime.close()
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await runtime.close()
        XCTFail("A journal continuity gap did not trigger one fresh authoritative opening cut")
    }
}
