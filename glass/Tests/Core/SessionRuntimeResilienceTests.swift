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

    func testRuntimeStreamInterruptionReconnectsAndUpdatesJournal() async throws {
        let mockController = MockSessionController()

        // 第一次连接：建立握手后正常结束流（模拟断网或服务端重置连接）
        await mockController.queueFollowStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.makeOpeningSnapshot(sessionID: "test-session", cursor: 1))
            continuation.finish()
            return stream
        }

        // 第二次连接（自动自愈）：重连成功，补充第二帧
        await mockController.queueFollowStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionFollowFrame, Error>.makeStream()
            continuation.yield(Self.makeOpeningSnapshot(sessionID: "test-session", cursor: 1))
            continuation.yield(Self.makeEventFrame(seq: 2))
            return stream
        }

        let runtime = SessionRuntime(
            controller: mockController,
            generation: RemoteConnectionGeneration(rawValue: 1),
            address: .session(sessionID: "test-session")
        )

        let initialSnapshot = try await runtime.open()
        guard case let .session(id) = initialSnapshot.address else {
            XCTFail("快照 address 必须为 session")
            return
        }
        XCTAssertEqual(id, "test-session")

        // 观察快照流：断网自愈后必须收到更新的 snapshot
        var receivedSnapshots: [SessionJournalSnapshot] = []
        let snapshotStream = await runtime.snapshots()

        let expectation = expectation(description: "自愈后接收到新快照")

        let observerTask = Task {
            for await snap in snapshotStream {
                receivedSnapshots.append(snap)
                if snap.records.count >= 2 {
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        observerTask.cancel()
        await runtime.close()

        let calls = await mockController.followCallCount
        XCTAssertGreaterThanOrEqual(calls, 2, "网络断开后必须触发自动重连自愈，严禁静默假死！")
    }
}
