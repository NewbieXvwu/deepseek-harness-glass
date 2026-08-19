import XCTest

@testable import GlassCore

final class ConversationCoreNodesTests: XCTestCase {
    func testUserContextAssistantThinkingAndFinalTailMaterializeWithoutDuplicateRows() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 1, type: "turn/start", data: ["turn": .number(1)]),
            event(seq: 2, type: "step/start", data: ["turn": .number(1), "step": .number(1)]),
            event(seq: 3, type: "user/message", surface: .string("append"), data: [
                "id": .string("u1"),
                "content": .array([text("hello")]),
                "source": .object(["kind": .string("user")])
            ]),
            event(seq: 4, type: "assistant/chunk", data: [
                "turn": .number(1), "step": .number(1),
                "chunk": .object(["type": .string("reasoning-delta"), "index": .number(0), "text": .string("plan")])
            ]),
            event(seq: 5, type: "assistant/chunk", data: [
                "turn": .number(1), "step": .number(1),
                "chunk": .object(["type": .string("text-delta"), "index": .number(1), "text": .string("answer")])
            ]),
            event(seq: 6, type: "assistant/message", surface: .string("append"), data: [
                "turn": .number(1), "step": .number(1),
                "message": .object(["id": .string("a1"), "content": .array([text("answer")])]),
                "usage": .object(["outputTokens": .number(7)])
            ])
        ]

        XCTAssertEqual(reducer.replaceWindow(Array(entries.prefix(4)).map { ConversationEventInput(event: $0) }, hasMore: false), .immediate)
        var chat = reducer.snapshot(target: "chat")
        XCTAssertEqual(chat.map(\.kind), ["user", "assistant-step"])
        let running = tryUnwrap(chat.last?.data as? CoreAssistantNode)
        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(running.blocks.map(\.kind), [.reasoning])

        XCTAssertEqual(reducer.append(.init(event: entries[4])), .animationFrame)
        XCTAssertEqual(reducer.append(.init(event: entries[5])), .immediate)
        chat = reducer.snapshot(target: "chat")
        XCTAssertEqual(chat.filter { $0.kind == "assistant-step" }.count, 1, "final assistant/message replaces the same step context rather than appending a duplicate stream tail")
        let settled = tryUnwrap(chat.last?.data as? CoreAssistantNode)
        XCTAssertEqual(settled.status, .settled)
        XCTAssertEqual(settled.messageID, "a1")
        XCTAssertEqual(settled.blocks.first?.text, "answer")
    }

    func testToolRetryErrorAndCompactionNodesUseOfficialCorrelations() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 10, type: "turn/start", data: ["turn": .number(2)]),
            event(seq: 11, type: "step/start", data: ["turn": .number(2), "step": .number(1)]),
            event(seq: 12, type: "tool/call", data: ["callId": .string("call-1"), "name": .string("search"), "arguments": .string("{\"q\":\"swift\"}"), "turn": .number(2), "step": .number(1)]),
            event(seq: 13, type: "tool/result", surface: .string("append"), data: [
                "message": .object([
                    "source": .object(["callId": .string("call-1")]),
                    "content": .array([text("result")])
                ])
            ]),
            event(seq: 14, type: "llm/retry", data: ["retryId": .string("retry-1"), "retry": .number(1), "turn": .number(2), "step": .number(1)]),
            event(seq: 15, type: "llm/retry-started", data: ["retryId": .string("retry-1"), "retry": .number(1), "turn": .number(2), "step": .number(1)]),
            event(seq: 16, type: "turn/end", data: [
                "turn": .number(2),
                "reason": .object(["kind": .string("error"), "error": .object(["message": .string("transport failed"), "code": .string("network")])])
            ]),
            event(seq: 17, type: "compaction/start", data: ["compactionId": .string("compact-1")]),
            event(seq: 18, type: "compaction/summary", data: ["compactionId": .string("compact-1"), "summary": .string("short summary"), "shadowedItemCount": .number(3), "shadowedTokenCount": .number(99)]),
            event(seq: 19, type: "user/message", surface: .object(["op": .string("replace"), "start": .number(1), "end": .number(9)]), data: [
                "id": .string("checkpoint"),
                "source": .object(["kind": .string("plugin"), "plugin": .string("compact"), "compactionId": .string("compact-1")]),
                "content": .array([])
            ])
        ]

        XCTAssertEqual(reducer.replaceWindow(entries.map { ConversationEventInput(event: $0) }, hasMore: true), .immediate)
        let chat = reducer.snapshot(target: "chat")

        let tool = tryUnwrap(chat.first(where: { $0.kind == "tool-call" })?.data as? CoreToolCallNode)
        XCTAssertEqual(tool.status, .settled)
        XCTAssertEqual(tool.callID, "call-1")
        XCTAssertEqual(tool.resultContent.first?.text, "result")

        let retry = tryUnwrap(chat.first(where: { $0.kind == "model-retry" })?.data as? CoreRetryNode)
        XCTAssertEqual(retry.attempts, [.init(seq: 14, time: 14, retry: 1, state: .started)])

        let error = tryUnwrap(chat.first(where: { $0.kind == "turn-error" })?.data as? CoreTurnErrorNode)
        XCTAssertEqual(error.message, "transport failed")
        XCTAssertTrue(error.hiddenByRetry, "a retry on the same turn suppresses the terminal error row")

        let compaction = tryUnwrap(chat.first(where: { $0.kind == "compaction" })?.data as? CoreCompactionNode)
        XCTAssertEqual(compaction.compactionID, "compact-1")
        XCTAssertEqual(compaction.summary, "short summary")
        XCTAssertEqual(compaction.shadowedItemCount, 3)
        XCTAssertEqual(compaction.shadowedTokenCount, 99)
        XCTAssertEqual(compaction.seq, 19, "checkpoint stays at its landed replacement event, not at summary")
    }

    func testClosedStepFreezesStreamingAssistantAndRunningToolAtOfficialSyntheticAnchors() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 60, type: "turn/start", data: ["turn": .number(3)]),
            event(seq: 61, type: "step/start", data: ["turn": .number(3), "step": .number(1)]),
            event(seq: 62, type: "assistant/chunk", data: [
                "turn": .number(3), "step": .number(1),
                "chunk": .object(["type": .string("text-delta"), "index": .number(0), "text": .string("partial")])
            ]),
            event(seq: 63, type: "tool/call", data: ["callId": .string("call-partial"), "name": .string("bash"), "arguments": .string("pwd"), "turn": .number(3), "step": .number(1)]),
            event(seq: 64, type: "step/end", data: ["turn": .number(3), "step": .number(1)])
        ]
        reducer.replaceWindow(entries.map { .init(event: $0) }, hasMore: false)
        let chat = reducer.snapshot(target: "chat")
        let assistant = tryUnwrap(chat.first(where: { $0.kind == "assistant-step" }))
        let tool = tryUnwrap(chat.first(where: { $0.kind == "tool-call" }))
        XCTAssertEqual((assistant.data as? CoreAssistantNode)?.status, .interrupted)
        XCTAssertEqual((tool.data as? CoreToolCallNode)?.status, .interrupted)
        XCTAssertEqual(tryUnwrap(assistant.anchorSeq), 63.1, accuracy: 0.0001)
        XCTAssertEqual(tryUnwrap(tool.anchorSeq), 63.2, accuracy: 0.0001)
    }

    func testContextInjectionIsAVisibleContextNodeNotAnOrdinaryUserBubble() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let injected = event(seq: 50, type: "user/message", surface: .string("append"), data: [
            "id": .string("ctx-1"),
            "content": .array([text("system reminder")]),
            "source": .object(["kind": .string("plugin"), "plugin": .string("agent-instructions")])
        ])
        reducer.replaceWindow([.init(event: injected)], hasMore: false)
        let node = tryUnwrap(reducer.snapshot(target: "chat").first?.data as? CoreUserMessageNode)
        XCTAssertEqual(node.kind, .context)
        XCTAssertEqual(node.sourcePlugin, "agent-instructions")
    }

    func testDurableNextStepInboxSpliceClassifiesOnlyClaimedUserMessageAsSteering() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 1, type: "agent/inbox/spliced", data: [
                "target": .string("next-step"),
                "start": .number(0),
                "removedCount": .number(0),
                "inserted": .array([.object(["id": .string("steer-me")])]),
            ]),
            event(seq: 2, type: "agent/inbox/spliced", data: [
                "target": .string("next-step"),
                "start": .number(0),
                "removedCount": .number(1),
                "inserted": .array([]),
            ]),
            event(seq: 3, type: "user/message", surface: .string("append"), data: [
                "id": .string("steer-me"),
                "content": .array([text("steer now")]),
                "source": .object(["kind": .string("user")]),
            ]),
            event(seq: 4, type: "user/message", surface: .string("append"), data: [
                "id": .string("ordinary"),
                "content": .array([text("ordinary turn")]),
                "source": .object(["kind": .string("user")]),
            ]),
        ]

        XCTAssertEqual(reducer.replaceWindow(entries.map { ConversationEventInput(event: $0) }, hasMore: false), .immediate)
        let chat = reducer.snapshot(target: "chat")
        XCTAssertEqual(chat.map(\.kind), ["steering", "user"])
        XCTAssertEqual((tryUnwrap(chat.first?.data as? CoreUserMessageNode)).kind, .steering)
        XCTAssertEqual((tryUnwrap(chat.last?.data as? CoreUserMessageNode)).kind, .user)
        XCTAssertEqual(reducer.snapshot(target: "timeline").count, 0)
    }

    func testCoreNodeReplaySnapshotsRemainStableAfterEveryOfficialAppend() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 1, type: "turn/start", data: ["turn": .number(9)]),
            event(seq: 2, type: "step/start", data: ["turn": .number(9), "step": .number(1)]),
            event(seq: 3, type: "user/message", surface: .string("append"), data: [
                "id": .string("u-replay"),
                "content": .array([text("question")]),
                "source": .object(["kind": .string("user")]),
            ]),
            event(seq: 4, type: "assistant/chunk", data: [
                "turn": .number(9), "step": .number(1),
                "chunk": .object(["type": .string("text-delta"), "index": .number(0), "text": .string("hel")]),
            ]),
            event(seq: 5, type: "assistant/chunk", data: [
                "turn": .number(9), "step": .number(1),
                "chunk": .object(["type": .string("text-delta"), "index": .number(0), "text": .string("lo")]),
            ]),
            event(seq: 6, type: "tool/call", data: [
                "callId": .string("call-replay"), "name": .string("read"), "arguments": .string("{\"path\":\"README.md\"}"),
                "turn": .number(9), "step": .number(1),
            ]),
            event(seq: 7, type: "tool/result", surface: .string("append"), data: [
                "message": .object([
                    "source": .object(["callId": .string("call-replay")]),
                    "content": .array([text("contents")]),
                ]),
            ]),
            event(seq: 8, type: "assistant/message", surface: .string("append"), data: [
                "turn": .number(9), "step": .number(1),
                "message": .object(["id": .string("a-replay"), "content": .array([text("final")])]),
            ]),
            event(seq: 9, type: "step/end", data: ["turn": .number(9), "step": .number(1)]),
        ]

        var publications: [ConversationPublication] = []
        var chatKindsAfterAppend: [[String]] = []
        for entry in entries {
            publications.append(reducer.append(.init(event: entry)))
            chatKindsAfterAppend.append(reducer.snapshot(target: "chat").map(\.kind))
        }
        XCTAssertEqual(publications, [.immediate, .none, .immediate, .animationFrame, .animationFrame, .immediate, .immediate, .immediate, .none])
        XCTAssertEqual(chatKindsAfterAppend, [
            [],
            [],
            ["user"],
            ["user", "assistant-step"],
            ["user", "assistant-step"],
            ["user", "assistant-step", "tool-call"],
            ["user", "assistant-step", "tool-call"],
            ["user", "tool-call", "assistant-step"],
            ["user", "tool-call", "assistant-step"],
        ])

        let chat = reducer.snapshot(target: "chat")
        XCTAssertEqual(chat.map(\.kind), ["user", "tool-call", "assistant-step"])
        XCTAssertEqual(chat.filter { $0.kind == "assistant-step" }.count, 1)
        XCTAssertEqual(chat.filter { $0.kind == "tool-call" }.count, 1)

        let user = tryUnwrap(chat.first(where: { $0.kind == "user" })?.data as? CoreUserMessageNode)
        XCTAssertEqual(user.messageID, "u-replay")
        XCTAssertEqual(user.content.first?.text, "question")

        let tool = tryUnwrap(chat.first(where: { $0.kind == "tool-call" })?.data as? CoreToolCallNode)
        XCTAssertEqual(tool.status, .settled)
        XCTAssertEqual(tool.callID, "call-replay")
        XCTAssertEqual(tool.resultContent.first?.text, "contents")

        let assistant = tryUnwrap(chat.first(where: { $0.kind == "assistant-step" })?.data as? CoreAssistantNode)
        XCTAssertEqual(assistant.status, .settled)
        XCTAssertEqual(assistant.messageID, "a-replay")
        XCTAssertEqual(assistant.blocks.first?.text, "final")
        XCTAssertEqual(reducer.rawWindow().map(\.event.seq), Array(1...9))
    }

    private func text(_ value: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(value)])
    }

    private func event(seq: Int, type: String, surface: JSONValue? = nil, data: [String: JSONValue]) -> SessionEventDTO {
        .init(type: type, seq: seq, time: Double(seq), data: .object(data), surfaceOp: surface)
    }

    private func tryUnwrap<T>(_ value: T?) -> T {
        guard let value else { fatalError("Expected non-nil fixture output") }
        return value
    }
}
