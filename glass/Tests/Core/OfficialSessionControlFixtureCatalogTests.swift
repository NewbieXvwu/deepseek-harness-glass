import Foundation
import XCTest

@testable import GlassCore

final class OfficialSessionControlFixtureCatalogTests: XCTestCase {
    private typealias ControlProvider = @Sendable () throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error>

    private final actor FixtureSessionController: SessionControllerAPI {
        private var controlStreams: [ControlProvider] = []
        private(set) var controlCallCount = 0

        func queueControlStream(_ provider: @escaping ControlProvider) {
            controlStreams.append(provider)
        }

        func control() async throws -> AsyncThrowingStream<RemoteSessionControlFrame, Error> {
            controlCallCount += 1
            guard !controlStreams.isEmpty else { throw FixtureError.missingControlStream }
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

    func testReplacementFixtureInstallsOpeningAndAppliesEveryDelta() async throws {
        let fixture = try OfficialSessionControlFixtureCatalog.load()
        let replay = try XCTUnwrap(fixture.cases.first { $0.id == "replacement-deltas-and-reconnect" })
        let frames = try XCTUnwrap(replay.streams.first)
        XCTAssertEqual(frames.count, 4)

        guard case let .baseline(baseline) = frames[0] else {
            return XCTFail("replacement fixture must start with the rc.1 control baseline")
        }
        guard case let .queue(queueSessionID, items) = frames[1] else {
            return XCTFail("replacement fixture must carry a queue replacement after baseline")
        }
        guard case let .jobs(jobsSessionID, jobs) = frames[2] else {
            return XCTFail("replacement fixture must carry a jobs replacement after queue")
        }
        guard case let .projection(projectionSessionID, key, value, seq) = frames[3] else {
            return XCTFail("replacement fixture must carry a projection replacement after jobs")
        }

        XCTAssertEqual(queueSessionID, "fixture-session")
        XCTAssertEqual(items.map(\.id), ["fixture-q-new"])
        XCTAssertEqual(items.map(\.placement), [.steering])
        XCTAssertEqual(jobsSessionID, "fixture-session")
        XCTAssertEqual(jobs.map(\.id), ["fixture-job-new"])
        XCTAssertEqual(jobs.map(\.status), [.completed])
        XCTAssertEqual(projectionSessionID, "fixture-session")
        XCTAssertEqual(key, "running")
        XCTAssertEqual(seq.rawValue, 2)

        let controller = FixtureSessionController()
        await controller.queueControlStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            for frame in frames { continuation.yield(frame) }
            return stream
        }
        let runtime = SessionControlRuntime(
            controller: controller,
            generation: RemoteConnectionGeneration(rawValue: 21)
        )

        let opening = try await runtime.open()
        XCTAssertEqual(opening.queues, baseline.queues)
        XCTAssertEqual(opening.jobs, baseline.jobs)
        XCTAssertEqual(opening.projections, baseline.projections)

        let updated = try await eventuallySnapshot(runtime) { snapshot in
            snapshot.queues[queueSessionID] == items
                && snapshot.jobs[jobsSessionID] == jobs
                && snapshot.projections[projectionSessionID]?.asOfSeq == seq
        }
        XCTAssertEqual(updated.queues[queueSessionID], items)
        XCTAssertEqual(updated.jobs[jobsSessionID], jobs)

        var expectedProjectionValues = baseline.projections[projectionSessionID]?.values ?? [:]
        expectedProjectionValues[key] = value
        XCTAssertEqual(
            updated.projections[projectionSessionID],
            RemoteSessionProjectionBaseline(asOfSeq: seq, values: expectedProjectionValues)
        )
        await runtime.invalidate()
    }

    func testEmptyOpeningFixtureInstallsEmptyAuthority() async throws {
        let fixture = try OfficialSessionControlFixtureCatalog.load()
        let replay = try XCTUnwrap(fixture.cases.first { $0.id == "empty-opening-baseline" })
        XCTAssertEqual(replay.streams.count, 1)
        let frames = try XCTUnwrap(replay.streams.first)
        XCTAssertEqual(frames.count, 1)
        let frame = try XCTUnwrap(frames.first)
        guard case let .baseline(baseline) = frame else {
            return XCTFail("empty opening fixture must contain one rc.1 control baseline")
        }
        XCTAssertTrue(baseline.queues.isEmpty)
        XCTAssertTrue(baseline.jobs.isEmpty)
        XCTAssertTrue(baseline.projections.isEmpty)

        let controller = FixtureSessionController()
        await controller.queueControlStream {
            let (stream, continuation) = AsyncThrowingStream<RemoteSessionControlFrame, Error>.makeStream()
            continuation.yield(frame)
            return stream
        }
        let runtime = SessionControlRuntime(
            controller: controller,
            generation: RemoteConnectionGeneration(rawValue: 22)
        )

        let opening = try await runtime.open()
        XCTAssertTrue(opening.queues.isEmpty)
        XCTAssertTrue(opening.jobs.isEmpty)
        XCTAssertTrue(opening.projections.isEmpty)
        let callCount = await controller.controlCallCount
        XCTAssertEqual(callCount, 1)
        await runtime.invalidate()
    }

    private func eventuallySnapshot(
        _ runtime: SessionControlRuntime,
        predicate: (SessionControlSnapshot) -> Bool
    ) async throws -> SessionControlSnapshot {
        for _ in 0..<100 {
            if let snapshot = await runtime.currentSnapshot(), predicate(snapshot) { return snapshot }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw FixtureError.snapshotTimeout
    }

    private enum FixtureError: Error {
        case missingControlStream
        case snapshotTimeout
    }
}
