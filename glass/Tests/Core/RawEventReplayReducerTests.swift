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

    func testConcurrentToolAndAssistantReplayPreservesBothTypedNodes() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "interleaved-tool-and-assistant")

        XCTAssertEqual(reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false), .immediate)
        let chat = reducer.snapshot(target: "chat")
        let tool = tryUnwrap(chat.first(where: { $0.kind == "tool-call" })?.data as? CoreToolCallNode)
        let assistant = tryUnwrap(chat.first(where: { $0.kind == "assistant-step" })?.data as? CoreAssistantNode)
        XCTAssertEqual(tool.callID, "fixture-call-1")
        XCTAssertEqual(tool.status, .settled)
        XCTAssertEqual(tool.resultContent.first?.text, "fixture result")
        XCTAssertEqual(assistant.status, .running)
        XCTAssertEqual(assistant.blocks.first?.text, "working")
        XCTAssertEqual(Set(chat.map(\.key)).count, chat.count)
    }

    func testLongSessionReplayMaterializesEveryTurnWithoutDuplicateKeys() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "long-session-template", expanded: true)

        XCTAssertEqual(reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false), .immediate)
        let chat = reducer.snapshot(target: "chat")
        XCTAssertEqual(events.count, 4_000)
        XCTAssertEqual(chat.count, 2_000)
        XCTAssertEqual(chat.filter { $0.kind == "user" }.count, 1_000)
        XCTAssertEqual(chat.filter { $0.kind == "assistant-step" }.count, 1_000)
        XCTAssertEqual(Set(chat.map(\.key)).count, chat.count)
        XCTAssertEqual((chat.first?.data as? CoreUserNode)?.blocks.first?.text, "fixture long request-1")
        XCTAssertEqual((chat.last?.data as? CoreAssistantNode)?.blocks.first?.text, "fixture long answer-1000")
    }

    func testLongSessionReplayPerformanceBaseline() throws {
        let events = try events(for: "long-session-template", expanded: true)
        measure(metrics: [XCTClockMetric()]) {
            let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
            _ = reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false)
            XCTAssertEqual(reducer.snapshot(target: "chat").count, 2_000)
        }
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

    private func events(for id: String, expanded: Bool = false) throws -> [SessionEventDTO] {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = tryUnwrap(fixture.cases.first(where: { $0.id == id }))
        let values = expanded ? OfficialRawEventReplayFixtureCatalog.expandedEvents(for: replay) : replay.events
        return try values.map { event in
            try JSONDecoder().decode(SessionEventDTO.self, from: JSONEncoder().encode(event))
        }
    }
}
