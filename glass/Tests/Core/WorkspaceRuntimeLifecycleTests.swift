import Foundation
import XCTest

@testable import GlassCore

final class WorkspaceRuntimeLifecycleTests: XCTestCase {
    func testStreamEndAfterBaselineInvalidatesPublishedAuthority() async throws {
        let source = WorkspaceFollowSource()
        let runtime = WorkspaceRuntime(controller: source)
        let generation = RemoteConnectionGeneration(rawValue: 11)
        let starting = Task { try await runtime.start(generation: generation) }

        source.continuation.yield(.baseline(.init(items: [], archivedSessionIds: [])))
        try await starting.value
        XCTAssertEqual(await runtime.current()?.generation, generation)

        source.continuation.finish()
        try await assertEventuallyInvalid(runtime)
    }

    func testSecondBaselineInvalidatesCurrentGeneration() async throws {
        let source = WorkspaceFollowSource()
        let runtime = WorkspaceRuntime(controller: source)
        let generation = RemoteConnectionGeneration(rawValue: 12)
        let starting = Task { try await runtime.start(generation: generation) }

        source.continuation.yield(.baseline(.init(items: [], archivedSessionIds: [])))
        try await starting.value
        XCTAssertEqual(await runtime.current()?.generation, generation)

        source.continuation.yield(.baseline(.init(items: [], archivedSessionIds: [])))
        try await assertEventuallyInvalid(runtime)
    }

    private func assertEventuallyInvalid(_ runtime: WorkspaceRuntime) async throws {
        for _ in 0..<100 {
            if await runtime.current() == nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Workspace authority remained published after the stream generation became invalid")
    }
}

private final class WorkspaceFollowSource: WorkspaceControllerAPI, @unchecked Sendable {
    let stream: AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>
    let continuation: AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>.Continuation

    init() {
        let pair = AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func follow() async throws -> AsyncThrowingStream<RemoteWorkspaceFollowFrame, Error> { stream }

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
