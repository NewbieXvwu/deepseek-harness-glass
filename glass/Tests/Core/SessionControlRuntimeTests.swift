import Foundation
import XCTest

@testable import GlassCore

final class SessionControlRuntimeTests: XCTestCase {
    private struct MockError: Error {}
    private typealias ControlProvider = @Sendable () throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error>

    private final actor MockSessionController: SessionControllerAPI {
        private var controlStreams: [ControlProvider] = []
        private(set) var controlCallCount = 0

        func queueControlStream(_ provider: @escaping ControlProvider) {
            controlStreams.append(provider)
        }

        func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error> {
            controlCallCount += 1
            guard !controlStreams.isEmpty else { throw MockError() }
            return try controlStreams.removeFirst()()
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
        func page(_ request: RemoteSessionPageRequest) async throws -> RemoteSessionPageValue { fatalError() }
        func follow(_ request: RemoteSessionFollowRequest) async throws -> AsyncThrowingStream<RemoteSessionFollowFrame, Error> { fatalError() }
    }

    func testOpeningBaselineInstallsCompleteGenerationSnapshot() async throws {
        let controller = MockSessionController()
        let baseline = RemoteSessionControlBaseline(
            queues: ["s1": [Self.queuedItem(id: "q1")]],
            jobs: ["s1": [Self.job(id: "j1", status: .running)]],
            projections: ["s1": .init(asOfSeq: SessionSeq(rawValue: 4), values: ["model": .string("a")])]
        )
        await controller.queueControlStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(.baseline(baseline))
            return stream
        }
        let runtime = SessionControlRuntime(
            controller: controller,
            generation: RemoteConnectionGeneration(rawValue: 11)
        )

        let opening = try await runtime.open()

        XCTAssertEqual(opening.generation, RemoteConnectionGeneration(rawValue: 11))
        XCTAssertEqual(opening.queues, baseline.queues)
        XCTAssertEqual(opening.jobs, baseline.jobs)
        XCTAssertEqual(opening.projections, baseline.projections)
        let callCount = await controller.controlCallCount
        XCTAssertEqual(callCount, 1)
        await runtime.invalidate()
    }

    func testControlRejectsDeltaBeforeOpeningBaseline() async {
        let controller = MockSessionController()
        await controller.queueControlStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(.queue(sessionID: "s1", items: []))
            continuation.finish()
            return stream
        }
        let runtime = SessionControlRuntime(
            controller: controller,
            generation: RemoteConnectionGeneration(rawValue: 1)
        )

        do {
            _ = try await runtime.open()
            XCTFail("control delta before baseline must fail the generation")
        } catch let error as SessionControlRuntimeError {
            XCTAssertEqual(error, .missingOpeningBaseline)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        let snapshot = await runtime.currentSnapshot()
        XCTAssertNil(snapshot)
    }

    func testQueueJobsAndProjectionFramesReplaceHostOwnedState() async throws {
        let controller = MockSessionController()
        await controller.queueControlStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(.baseline(.init(
                queues: ["s1": [Self.queuedItem(id: "old-q")]],
                jobs: ["s1": [Self.job(id: "old-j", status: .running)]],
                projections: ["s1": .init(
                    asOfSeq: SessionSeq(rawValue: 3),
                    values: ["model": .string("a"), "permissions": .string("workspace")]
                )]
            )))
            continuation.yield(.queue(sessionID: "s1", items: [Self.queuedItem(id: "new-q")]))
            continuation.yield(.jobs(sessionID: "s1", jobs: [Self.job(id: "new-j", status: .completed)]))
            continuation.yield(.projection(
                sessionID: "s1",
                key: "model",
                value: .string("b"),
                seq: SessionSeq(rawValue: 4)
            ))
            return stream
        }
        let runtime = SessionControlRuntime(
            controller: controller,
            generation: RemoteConnectionGeneration(rawValue: 2)
        )

        _ = try await runtime.open()
        let updated = try await eventuallySnapshot(runtime) { snapshot in
            snapshot.queues["s1"]?.first?.id == "new-q"
                && snapshot.jobs["s1"]?.first?.id == "new-j"
                && snapshot.projections["s1"]?.asOfSeq == SessionSeq(rawValue: 4)
        }

        XCTAssertEqual(updated.queues["s1"], [Self.queuedItem(id: "new-q")])
        XCTAssertEqual(updated.jobs["s1"], [Self.job(id: "new-j", status: .completed)])
        XCTAssertEqual(updated.projections["s1"]?.values["model"], .string("b"))
        XCTAssertEqual(updated.projections["s1"]?.values["permissions"], .string("workspace"))
        await runtime.invalidate()
    }

    func testInvalidateDropsTransientAuthorityImmediately() async throws {
        let controller = MockSessionController()
        await controller.queueControlStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(.baseline(.init(
                queues: ["s1": [Self.queuedItem(id: "q1")]],
                jobs: ["s1": [Self.job(id: "j1", status: .running)]],
                projections: [:]
            )))
            return stream
        }
        let runtime = SessionControlRuntime(
            controller: controller,
            generation: RemoteConnectionGeneration(rawValue: 5)
        )
        _ = try await runtime.open()
        let opening = await runtime.currentSnapshot()
        XCTAssertNotNil(opening)

        await runtime.invalidate()

        let invalidated = await runtime.currentSnapshot()
        XCTAssertNil(invalidated)
    }

    func testNormalControlStreamEndRetainsAuthorityAndReconnects() async throws {
        let controller = MockSessionController()
        await controller.queueControlStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(.baseline(.init(queues: [:], jobs: [:], projections: [:])))
            continuation.finish()
            return stream
        }
        let runtime = SessionControlRuntime(
            controller: controller,
            generation: RemoteConnectionGeneration(rawValue: 8)
        )

        _ = try await runtime.open()
        for _ in 0..<200 {
            if await controller.controlCallCount >= 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let calls = await controller.controlCallCount
        XCTAssertGreaterThanOrEqual(calls, 2, "an ended control stream must be reopened")
        let retained = await runtime.currentSnapshot()
        XCTAssertNotNil(retained, "a transient end must not drop retained authority")
    }

    private static func queuedItem(id: String) -> RemoteSessionQueuedItem {
        .init(
            id: id,
            placement: .queued,
            rpcId: SessionRequestID(rawValue: "rpc-\(id)"),
            message: .init(id: "message-\(id)", content: [.string(id)])
        )
    }

    private static func job(id: String, status: RemoteSessionJob.Status) -> RemoteSessionJob {
        .init(
            id: id,
            kind: "bash",
            label: id,
            status: status,
            detail: nil,
            startedAt: 1,
            finishedAt: status == .running ? nil : 2
        )
    }

    private func eventuallySnapshot(
        _ runtime: SessionControlRuntime,
        predicate: (SessionControlSnapshot) -> Bool
    ) async throws -> SessionControlSnapshot {
        for _ in 0..<100 {
            if let snapshot = await runtime.currentSnapshot(), predicate(snapshot) { return snapshot }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw MockError()
    }
}
