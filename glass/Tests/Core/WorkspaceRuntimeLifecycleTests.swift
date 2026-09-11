import Foundation
import XCTest

@testable import GlassCore

final class WorkspaceRuntimeLifecycleTests: XCTestCase {
    func testStreamEndKeepsAuthorityAndReconnectsWithABackoffLoop() async throws {
        let source = WorkspaceFollowSource()
        let runtime = WorkspaceRuntime(controller: source)
        let generation = RemoteConnectionGeneration(rawValue: 11)
        let starting = Task { try await runtime.start(generation: generation) }

        try await yieldOpening(to: source)
        try await starting.value
        let opened = await runtime.current()
        XCTAssertEqual(opened?.generation, generation)

        try await finishStream(of: source)
        try await waitUntil("runtime re-follows after a normal stream end") { await source.followCount >= 2 }
        let retained = await runtime.current()
        XCTAssertNotNil(retained, "a transient carrier end must not blank the workspace")
    }

    func testReconnectBaselineReplacesRetainedAuthority() async throws {
        let fixture = try OfficialWorkspaceFollowFixtureCatalog.load()
        let replay = try XCTUnwrap(fixture.cases.first { $0.id == "reconnect-replacement-baseline" })
        XCTAssertEqual(replay.streams.count, 2)
        let first = try XCTUnwrap(replay.streams.first?.first)
        let second = try XCTUnwrap(replay.streams.last?.first)

        let source = WorkspaceFollowSource()
        let runtime = WorkspaceRuntime(controller: source)
        let generation = RemoteConnectionGeneration(rawValue: 13)
        let starting = Task { try await runtime.start(generation: generation) }

        try await yieldFrame(first, to: source)
        try await starting.value
        let retained = await runtime.current()
        XCTAssertEqual(retained?.items.map(\.workspaceId), ["old"])
        XCTAssertEqual(retained?.archivedSessionIDs, ["s-old"])

        try await finishStream(of: source)
        try await waitUntil("runtime re-follows after a normal stream end") { await source.followCount >= 2 }
        try await yieldFrame(second, to: source)
        try await waitUntil("reconnect baseline is installed") {
            let current = await runtime.current()
            return current?.items.map(\.workspaceId) == ["new"] && current?.archivedSessionIDs.isEmpty == true
        }
        let recovered = await runtime.current()
        XCTAssertEqual(recovered?.generation, generation)
    }

    func testOfficialClosedIncrementFixtureReplaysThroughRuntime() async throws {
        let fixture = try OfficialWorkspaceFollowFixtureCatalog.load()
        let replay = try XCTUnwrap(fixture.cases.first { $0.id == "closed-increment-union" })
        XCTAssertEqual(replay.streams.count, 1)
        let frames = try XCTUnwrap(replay.streams.first)
        XCTAssertEqual(frames.count, 6)
        let opening = try XCTUnwrap(frames.first)

        let source = WorkspaceFollowSource()
        let runtime = WorkspaceRuntime(controller: source)
        let generation = RemoteConnectionGeneration(rawValue: 15)
        let starting = Task { try await runtime.start(generation: generation) }

        try await yieldFrame(opening, to: source)
        try await starting.value
        for frame in frames.dropFirst() {
            try await yieldFrame(frame, to: source)
        }

        try await waitUntil("official workspace fixture applies every closed increment") {
            let current = await runtime.current()
            return current?.items.map(\.workspaceId) == ["c", "a"]
                && current?.items.last?.title == "A renamed"
                && current?.archivedSessionIDs == ["s-old"]
        }
        let replayed = await runtime.current()
        XCTAssertEqual(replayed?.generation, generation)
        let followCount = await source.followCount
        XCTAssertEqual(followCount, 1)
    }

    func testSecondBaselineOnOneStreamReplacesCurrentBaseline() async throws {
        let source = WorkspaceFollowSource()
        let runtime = WorkspaceRuntime(controller: source)
        let generation = RemoteConnectionGeneration(rawValue: 12)
        let starting = Task { try await runtime.start(generation: generation) }

        try await yieldOpening(to: source)
        try await starting.value

        let workspace = RemoteWorkspaceView(
            workspaceId: "ws-2",
            path: "/path/2",
            title: "Workspace 2",
            sessionIds: [],
            createdAt: "2026-09-08T00:00:00Z",
            updatedAt: "2026-09-08T00:00:00Z"
        )
        try await yieldFrame(.baseline(.init(items: [workspace], archivedSessionIds: [])), to: source)
        try await waitUntil("second baseline replaces the first") {
            let current = await runtime.current()
            return current?.items.map(\.workspaceId) == ["ws-2"]
        }
        let updated = await runtime.current()
        XCTAssertEqual(updated?.generation, generation)
    }

    func testStopClearsPublishedAuthority() async throws {
        let source = WorkspaceFollowSource()
        let runtime = WorkspaceRuntime(controller: source)
        let generation = RemoteConnectionGeneration(rawValue: 14)
        let starting = Task { try await runtime.start(generation: generation) }
        try await yieldOpening(to: source)
        try await starting.value

        await runtime.stop()
        let stopped = await runtime.current()
        XCTAssertNil(stopped)
    }

    private func yieldOpening(to source: WorkspaceFollowSource) async throws {
        try await yieldFrame(.baseline(.init(items: [], archivedSessionIds: [])), to: source)
    }

    private func yieldFrame(_ frame: RemoteWorkspaceFollowFrame, to source: WorkspaceFollowSource) async throws {
        try await waitUntil("follow stream is opened") { await source.continuation != nil }
        await source.continuation?.yield(frame)
    }

    private func finishStream(of source: WorkspaceFollowSource) async throws {
        try await waitUntil("follow stream is opened") { await source.continuation != nil }
        await source.continuation?.finish()
    }

    private func waitUntil(
        _ message: String,
        iterations: Int = 300,
        condition: () async -> Bool
    ) async throws {
        for _ in 0..<iterations {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(message)
    }
}

/// Hands out a fresh stream per `follow()` call so a reconnect can be observed.
private actor WorkspaceFollowSource: WorkspaceControllerAPI {
    private var latestContinuation: AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>.Continuation?
    private var followCalls = 0

    var continuation: AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>.Continuation? {
        latestContinuation
    }

    var followCount: Int { followCalls }

    func follow() async throws -> AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error> {
        let pair = AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>.makeStream()
        latestContinuation = pair.continuation
        followCalls += 1
        return pair.stream
    }

    func create(path: String) async throws -> RemoteWorkspaceCreateValue { throw WorkspaceFollowSourceError.unused }
    func rename(workspaceID: String, title: String) async throws -> RemoteWorkspaceValue { throw WorkspaceFollowSourceError.unused }
    func delete(workspaceID: String) async throws -> RemoteWorkspaceDeleteValue { throw WorkspaceFollowSourceError.unused }
    func insertBefore(workspaceID: String, beforeWorkspaceID: String?) async throws -> RemoteWorkspaceOrderValue { throw WorkspaceFollowSourceError.unused }
    func insertSessionBefore(workspaceID: String, sessionID: String, beforeSessionID: String?) async throws -> RemoteWorkspaceValue { throw WorkspaceFollowSourceError.unused }
    func archiveSession(sessionID: String) async throws -> RemoteWorkspaceArchiveValue { throw WorkspaceFollowSourceError.unused }
}

private enum WorkspaceFollowSourceError: Error {
    case unused
}
