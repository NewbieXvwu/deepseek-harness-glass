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

        let final = try tryUnwrap(snapshots.last)
        XCTAssertEqual(final.map(\.kind), ["user", "assistant-step"])
        XCTAssertEqual(final.map(\.key), [
            conversationContextKey(kind: "input-message", id: "fixture-user-1"),
            conversationContextKey(kind: "assistant-step", id: "1:1"),
        ])
        XCTAssertEqual(Set(final.map(\.key)).count, final.count)
        let assistant = try tryUnwrap(final.last?.data as? CoreAssistantNode)
        XCTAssertEqual(assistant.status, .settled)
        XCTAssertEqual(assistant.blocks.map(\.kind), [.text])
        XCTAssertEqual(assistant.blocks.first?.text, "fixture answer")
        XCTAssertEqual(snapshots.dropLast().flatMap { $0 }.filter { $0.kind == "assistant-step" }.map(\.key).last, final.last?.key)
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
    }

    func testRetryErrorReplayCancelsScheduledAttemptAtHostTurnClosure() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "retry-error-turn")

        XCTAssertEqual(reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false), .immediate)
        let chat = reducer.snapshot(target: "chat")
        let retryNode = try tryUnwrap(chat.first(where: { $0.kind == "model-retry" }))
        let retry = try tryUnwrap(retryNode.data as? CoreRetryNode)
        XCTAssertEqual(chat.filter { $0.kind == "model-retry" }.count, 1)
        XCTAssertEqual(retryNode.key, conversationContextKey(kind: "model-retry", id: "fixture-retry-1"))
        XCTAssertEqual(retry.attempts.map(\.state), [.cancelled])
        XCTAssertEqual(retry.attempts.first?.failureMessage, "fixture transport failure")
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
    }

    func testRetryErrorReplaySnapshotsExposeScheduledThenCancelledHostAttempt() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "retry-error-turn")
        var snapshots: [[ConversationViewNode]] = []

        for event in events {
            _ = reducer.append(.init(event: event))
            snapshots.append(reducer.snapshot(target: "chat"))
        }

        XCTAssertTrue(snapshots[0].isEmpty)
        XCTAssertTrue(snapshots[1].isEmpty)
        let scheduled = try tryUnwrap(snapshots[2].first(where: { $0.kind == "model-retry" })?.data as? CoreRetryNode)
        XCTAssertEqual(scheduled.attempts.map(\.state), [.scheduled])
        let cancelled = try tryUnwrap(snapshots[3].first(where: { $0.kind == "model-retry" })?.data as? CoreRetryNode)
        XCTAssertEqual(cancelled.attempts.map(\.state), [.cancelled])
        XCTAssertEqual(snapshots[2].first(where: { $0.kind == "model-retry" })?.key, conversationContextKey(kind: "model-retry", id: "fixture-retry-1"))
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
    }

    func testReconnectReplayDeduplicatesRepeatedSequenceWithoutLosingLiveAssistantTail() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "reconnect-duplicate-sequence")

        XCTAssertEqual(reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false), .immediate)
        let chat = reducer.snapshot(target: "chat")
        let assistant = try tryUnwrap(chat.first?.data as? CoreAssistantNode)

        XCTAssertEqual(chat.map(\.kind), ["assistant-step"])
        XCTAssertEqual(chat.map(\.key), [conversationContextKey(kind: "assistant-step", id: "3:1")])
        XCTAssertEqual(assistant.status, .running)
        XCTAssertEqual(assistant.blocks.first?.text, "first second")
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
    }

    func testReconnectReplaySnapshotsDropDuplicateChunkBeforeAcceptingLiveTail() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "reconnect-duplicate-sequence")
        var snapshots: [[ConversationViewNode]] = []

        for event in events {
            _ = reducer.append(.init(event: event))
            snapshots.append(reducer.snapshot(target: "chat"))
        }

        XCTAssertTrue(snapshots[0].isEmpty)
        XCTAssertTrue(snapshots[1].isEmpty)
        let firstTail = try tryUnwrap(snapshots[2].first?.data as? CoreAssistantNode)
        XCTAssertEqual(firstTail.blocks.first?.text, "first")
        XCTAssertEqual(snapshots[3].map(\.key), snapshots[2].map(\.key))
        let deduplicatedTail = try tryUnwrap(snapshots[3].first?.data as? CoreAssistantNode)
        XCTAssertEqual(deduplicatedTail.blocks.first?.text, "first")
        let liveTail = try tryUnwrap(snapshots[4].first?.data as? CoreAssistantNode)
        XCTAssertEqual(liveTail.blocks.first?.text, "first second")
        XCTAssertEqual(liveTail.status, .running)
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
    }

    func testConcurrentToolAndAssistantReplayPreservesBothTypedNodes() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "interleaved-tool-and-assistant")

        XCTAssertEqual(reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false), .immediate)
        let chat = reducer.snapshot(target: "chat")
        let tool = try tryUnwrap(chat.first(where: { $0.kind == "tool-call" })?.data as? CoreToolCallNode)
        let assistant = try tryUnwrap(chat.first(where: { $0.kind == "assistant-step" })?.data as? CoreAssistantNode)
        XCTAssertEqual(chat.map(\.kind), ["tool-call", "assistant-step"])
        XCTAssertEqual(chat.map(\.key), [
            conversationContextKey(kind: "tool-call", id: "fixture-call-1"),
            conversationContextKey(kind: "assistant-step", id: "4:1"),
        ])
        XCTAssertEqual(tool.callID, "fixture-call-1")
        XCTAssertEqual(tool.status, .settled)
        XCTAssertEqual(tool.resultContent.first?.text, "fixture result")
        XCTAssertEqual(assistant.status, .running)
        XCTAssertEqual(assistant.blocks.first?.text, "working")
        XCTAssertEqual(Set(chat.map(\.key)).count, chat.count)
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
    }

    func testConcurrentReplaySnapshotsPreserveToolAndAssistantLifecycleBoundaries() throws {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let events = try events(for: "interleaved-tool-and-assistant")
        var snapshots: [[ConversationViewNode]] = []

        for event in events {
            _ = reducer.append(.init(event: event))
            snapshots.append(reducer.snapshot(target: "chat"))
        }

        XCTAssertTrue(snapshots[0].isEmpty)
        XCTAssertTrue(snapshots[1].isEmpty)
        let runningTool = try tryUnwrap(snapshots[2].first?.data as? CoreToolCallNode)
        XCTAssertEqual(snapshots[2].map(\.kind), ["tool-call"])
        XCTAssertEqual(runningTool.status, .running)
        XCTAssertEqual(snapshots[3].map(\.kind), ["tool-call", "assistant-step"])
        let runningAssistant = try tryUnwrap(snapshots[3].last?.data as? CoreAssistantNode)
        XCTAssertEqual(runningAssistant.status, .running)
        XCTAssertEqual(runningAssistant.blocks.first?.text, "working")
        let settledTool = try tryUnwrap(snapshots[4].first?.data as? CoreToolCallNode)
        XCTAssertEqual(settledTool.status, .settled)
        XCTAssertEqual(settledTool.resultContent.first?.text, "fixture result")
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
    }




    func testTenThousandStreamingChunksPerformanceBaselineKeepsOneAssistantRow() {
        var events = [
            SessionEventDTO(
                type: "step/start",
                seq: 1,
                time: 1,
                data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                ])
            )
        ]
        events += (1 ... 10_000).map { index in
            SessionEventDTO(
                type: "assistant/chunk",
                seq: index + 1,
                time: Double(index + 1),
                data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "chunk": .object([
                        "type": .string("text-delta"),
                        "index": .number(0),
                        "text": .string("x"),
                    ]),
                ])
            )
        }
        measure(metrics: [XCTClockMetric()]) {
            let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
            _ = reducer.replaceWindow(events.map { .init(event: $0) }, hasMore: false)
            XCTAssertEqual(reducer.snapshot(target: "chat").filter { $0.kind == "assistant-step" }.count, 1)
        }
    }

    func testUnknownReplayEventIsSafelyIgnoredWithoutManufacturingANode() throws {
        let events = try events(for: "unknown-node-safe-ignore")
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())

        for event in events {
            _ = reducer.append(.init(event: event))
        }

        XCTAssertTrue(reducer.snapshot(target: "chat").isEmpty)
        XCTAssertTrue(reducer.snapshot(target: "inspector").isEmpty)
        XCTAssertEqual(reducer.rawWindow().map(\.event.type), ["plugin/future-node"])
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try XCTUnwrap(value, "Expected non-nil value", file: file, line: line)
    }

    private func events(for id: String, expanded: Bool = false) throws -> [SessionEventDTO] {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = try tryUnwrap(fixture.cases.first(where: { $0.id == id }))
        let values = expanded ? OfficialRawEventReplayFixtureCatalog.expandedEvents(for: replay) : replay.events
        return try values.map { event in
            try JSONDecoder().decode(SessionEventDTO.self, from: JSONEncoder().encode(event))
        }
    }
}
