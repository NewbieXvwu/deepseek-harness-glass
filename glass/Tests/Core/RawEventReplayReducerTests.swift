import XCTest

@testable import GlassCore

final class RawEventReplayReducerTests: XCTestCase {
    func testHappyStreamingReplayMaintainsOneKeyedAssistantRowAcrossEveryAppend() throws {
        let events = try events(for: "happy-streaming-turn")
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        var snapshots: [[ConversationViewNode]] = []

        for event in events {
            _ = reducer.append(.init(event: event))
            snapshots.append(reducer.snapshot(target: "chat"))
        }

        let final = tryUnwrap(snapshots.last)
        XCTAssertEqual(final.map(\.kind), ["user", "assistant-step"])
        XCTAssertEqual(Set(final.map(\.key)).count, final.count)
        let assistant = tryUnwrap(final.last?.data as? CoreAssistantNode)
        XCTAssertEqual(assistant.status, .settled)
        XCTAssertEqual(assistant.blocks.map(\.kind), [.text])
        XCTAssertEqual(assistant.blocks.first?.text, "fixture answer")
        XCTAssertEqual(snapshots.dropLast().flatMap { $0 }.filter { $0.kind == "assistant-step" }.map(\.key).last, final.last?.key)
    }

    func testRetryErrorReplayCancelsScheduledAttemptAtHostTurnClosure() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "retry-error-turn")

        XCTAssertEqual(reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false), .immediate)
        let retry = tryUnwrap(reducer.snapshot(target: "chat").first(where: { $0.kind == "model-retry" })?.data as? CoreRetryNode)
        XCTAssertEqual(retry.attempts.map(\.state), [.cancelled])
        XCTAssertEqual(retry.attempts.first?.failureMessage, "fixture transport failure")
        XCTAssertEqual(reducer.snapshot(target: "chat").filter { $0.kind == "model-retry" }.count, 1)
    }

    func testUnknownReplayEventIsSafelyIgnoredWithoutManufacturingANode() throws {
        let events = try events(for: "unknown-node-safe-ignore")
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())

        for event in events {
            XCTAssertEqual(reducer.append(.init(event: event)), .immediate)
        }

        XCTAssertTrue(reducer.snapshot(target: "chat").isEmpty)
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
        XCTAssertEqual(reducer.rawWindow().map(\.event.type), ["plugin/future-node"])
    }

    private func events(for id: String) throws -> [SessionEventDTO] {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = tryUnwrap(fixture.cases.first(where: { $0.id == id }))
        return try replay.events.map { event in
            try JSONDecoder().decode(SessionEventDTO.self, from: JSONEncoder().encode(event))
        }
    }
}
