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
        XCTAssertEqual(settled.blocks.map(\.kind), [.text], "a final Host assistant message must replace transient reasoning rather than leak it into the settled row")
        XCTAssertEqual(settled.blocks.first?.text, "answer")
        XCTAssertFalse(settled.blocks.contains { $0.text?.contains("plan") ?? false }, "transient reasoning text must not remain visible after the final message settles")
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
            event(seq: 14, type: "llm/retry", data: ["retryId": .string("retry-1"), "retry": .number(1), "turn": .number(2), "step": .number(1), "mode": .string("normal"), "maxRetries": .number(3), "delayMs": .number(1_250), "failure": .object(["message": .string("provider busy"), "code": .string("rate_limit")])]),
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
        XCTAssertEqual(retry.attempts, [.init(seq: 14, time: 14, retry: 1, state: .started, delayMilliseconds: 1_250, failureMessage: "provider busy", maximumRetries: 3, unlimited: false)])

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

    func testScheduledRetryBecomesCancelledWhenHostClosesItsStep() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 30, type: "turn/start", data: ["turn": .number(4)]),
            event(seq: 31, type: "step/start", data: ["turn": .number(4), "step": .number(2)]),
            event(seq: 32, type: "llm/retry", data: [
                "retryId": .string("retry-cancelled"), "retry": .number(1), "turn": .number(4), "step": .number(2),
                "maxRetries": .number(3), "delayMs": .number(1_000), "failure": .object(["message": .string("busy")]),
            ]),
            event(seq: 33, type: "step/end", data: ["turn": .number(4), "step": .number(2)]),
        ]

        XCTAssertEqual(reducer.replaceWindow(entries.map { .init(event: $0) }, hasMore: false), .immediate)
        let retry = tryUnwrap(reducer.snapshot(target: "chat").first(where: { $0.kind == "model-retry" })?.data as? CoreRetryNode)
        XCTAssertEqual(retry.attempts.map(\.state), [.cancelled])
        XCTAssertEqual(retry.attempts.first?.delayMilliseconds, 1_000)
    }

    func testTurnMaxTokensNoticeUsesClosingTurnCoordinatesAndRejectsOtherEndReasons() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 40, type: "turn/start", data: ["turn": .number(6)]),
            event(seq: 41, type: "step/start", data: ["turn": .number(6), "step": .number(3)]),
            event(seq: 42, type: "assistant/message", surface: .string("append"), data: [
                "turn": .number(6), "step": .number(3),
                "message": .object(["id": .string("cap-answer"), "content": .array([text("partial")])]),
            ]),
            event(seq: 43, type: "turn/end", data: [
                "turn": .number(6),
                "reason": .object(["kind": .string("max-tokens")]),
            ]),
            event(seq: 44, type: "turn/end", data: [
                "turn": .number(7),
                "reason": .object(["kind": .string("cancelled")]),
            ]),
        ]

        XCTAssertEqual(reducer.replaceWindow(entries.map { .init(event: $0) }, hasMore: false), .immediate)
        let notice = tryUnwrap(reducer.snapshot(target: "chat").first(where: { $0.kind == "turn-max-tokens" }))
        let payload = tryUnwrap(notice.data as? CoreTurnMaxTokensNode)
        XCTAssertEqual(payload.turn, 6)
        XCTAssertEqual(payload.step, 3)
        XCTAssertEqual(payload.seq, 43)
        XCTAssertEqual(payload.time, 43)
        XCTAssertEqual(notice.anchorSeq, 43)
        XCTAssertEqual(reducer.snapshot(target: "chat").filter { $0.kind == "turn-max-tokens" }.count, 1)
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

        let trajectory = reducer.snapshot(target: "trajectory")
        XCTAssertEqual(trajectory.map(\.kind), ["trajectory-input-message", "trajectory-input-message"])
        XCTAssertEqual(trajectory.map(\.anchorSeq), [3, 4])
        XCTAssertEqual((tryUnwrap(trajectory.first?.data as? CoreUserMessageNode)).kind, .steering)
        XCTAssertEqual((tryUnwrap(trajectory.last?.data as? CoreUserMessageNode)).kind, .user)
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

    func testWorkflowRunFoldsOfficialDurableEventsWithExactPhaseIdentityAndTerminalStatuses() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 100, type: "tool-workflow/run-start", data: ["runId": .string("run-1"), "name": .string("release")]),
            event(seq: 101, type: "tool-workflow/agent-start", data: ["runId": .string("run-1"), "seq": .number(1), "label": .string("plan"), "childId": .string("child-1")]),
            event(seq: 102, type: "tool-workflow/agent-start", data: ["runId": .string("run-1"), "seq": .number(2), "label": .string(""), "phase": .string(""), "childId": .string("child-2")]),
            event(seq: 103, type: "tool-workflow/agent-start", data: ["runId": .string("run-1"), "seq": .number(3), "label": .string("ship"), "phase": .string("deliver"), "childId": .string("child-3")]),
            event(seq: 104, type: "tool-workflow/agent-end", data: ["runId": .string("run-1"), "seq": .number(1), "outcome": .string("completed")]),
            event(seq: 105, type: "tool-workflow/agent-end", data: ["runId": .string("run-1"), "seq": .number(2), "outcome": .string("failed")]),
            event(seq: 106, type: "tool-workflow/agent-end", data: ["runId": .string("run-1"), "seq": .number(3), "outcome": .string("cancelled")]),
            event(seq: 107, type: "tool-workflow/run-end", data: ["runId": .string("run-1"), "stopReason": .string("error")]),
        ]

        XCTAssertEqual(reducer.replaceWindow(entries.map { .init(event: $0) }, hasMore: false), .immediate)
        let workflow = tryUnwrap(reducer.snapshot(target: "chat").first(where: { $0.kind == "workflow-run" })?.data as? CoreWorkflowRunNode)
        XCTAssertEqual(workflow.name, "release")
        XCTAssertEqual(workflow.status, .failed)
        XCTAssertEqual(workflow.phases.map(\.key), ["missing", "value:0:", "value:7:deliver"])
        XCTAssertEqual(workflow.phases.flatMap(\.members).map(\.status), [.completed, .failed, .cancelled])
        XCTAssertEqual(workflow.phases.flatMap(\.members).map(\.childID), ["child-1", "child-2", "child-3"])
        XCTAssertEqual(workflowPhaseKey(nil), "missing")
        XCTAssertEqual(workflowPhaseKey(""), "value:0:")
        XCTAssertEqual(workflowPhaseKey("deliver"), "value:7:deliver")
        XCTAssertEqual(workflowPhaseKey("🚀"), "value:2:🚀", "matches JavaScript UTF-16 String.length")
    }

    func testWorkflowRunRejectsMalformedUpdatesAndProjectsInterruptedAtClosedLocation() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries = [
            event(seq: 200, type: "turn/start", data: ["turn": .number(7)]),
            event(seq: 201, type: "step/start", data: ["turn": .number(7), "step": .number(1)]),
            event(seq: 202, type: "tool-workflow/run-start", data: ["runId": .string("run-2"), "name": .string("" )]),
            event(seq: 203, type: "tool-workflow/agent-start", data: ["runId": .string("run-2"), "seq": .number(1), "label": .string("inspect"), "childId": .string("child-4")]),
            // Unknown outcome and a duplicate member sequence must not mutate the
            // typed renderer state or create phantom rows.
            event(seq: 204, type: "tool-workflow/agent-end", data: ["runId": .string("run-2"), "seq": .number(1), "outcome": .string("future-outcome")]),
            event(seq: 205, type: "tool-workflow/agent-start", data: ["runId": .string("run-2"), "seq": .number(1), "label": .string("duplicate"), "childId": .string("child-5")]),
            event(seq: 206, type: "step/end", data: ["turn": .number(7), "step": .number(1)]),
        ]

        for entry in entries { _ = reducer.append(.init(event: entry)) }
        let workflow = tryUnwrap(reducer.snapshot(target: "chat").first(where: { $0.kind == "workflow-run" })?.data as? CoreWorkflowRunNode)
        XCTAssertEqual(workflow.name, "")
        XCTAssertEqual(workflow.status, .interrupted)
        XCTAssertEqual(workflow.phases.flatMap(\.members).count, 1)
        XCTAssertEqual(workflow.phases.flatMap(\.members).first?.status, .interrupted)
    }

    func testDeliverablesPublishesSuccessfulMutationPathsAsTurnDataOnly() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries: [ConversationEventInput] = [
            .init(event: event(seq: 300, type: "turn/start", data: ["turn": .number(4)])),
            .init(event: event(seq: 301, type: "tool/call", data: ["turn": .number(4), "callId": .string("write"), "name": .string("write")]), view: toolView("call", [
                "card": .string("diff"),
                "locations": .array([.object(["path": .string("out/index.html")]), .object(["path": .string("notes.md")])]),
            ])),
            .init(event: toolResult(seq: 302, turn: 4, callID: "write")),
            .init(event: event(seq: 303, type: "tool/call", data: ["turn": .number(4), "callId": .string("edit"), "name": .string("edit")]), view: toolView("call", [
                "card": .string("generic"), "kind": .string("edit"),
                "locations": .array([.object(["path": .string("out/index.html")]), .object(["path": .string("out/app.css")])]),
            ])),
            .init(event: toolResult(seq: 304, turn: 4, callID: "edit")),
            .init(event: event(seq: 305, type: "tool/call", data: ["turn": .number(4), "callId": .string("read"), "name": .string("read")]), view: toolView("call", [
                "card": .string("generic"), "kind": .string("read"),
                "locations": .array([.object(["path": .string("ignored.md")])]),
            ])),
            .init(event: toolResult(seq: 306, turn: 4, callID: "read")),
            .init(event: event(seq: 307, type: "tool/call", data: ["turn": .number(4), "callId": .string("failed"), "name": .string("write")]), view: toolView("call", [
                "card": .string("diff"), "locations": .array([.object(["path": .string("failed.md")])]),
            ])),
            .init(event: toolResult(seq: 308, turn: 4, callID: "failed", isError: true)),
            // A mutation request which never receives a successful result before
            // the turn closes is cancelled/interrupted, not a produced file.
            .init(event: event(seq: 309, type: "tool/call", data: ["turn": .number(4), "callId": .string("cancelled"), "name": .string("write")]), view: toolView("call", [
                "card": .string("diff"), "locations": .array([.object(["path": .string("cancelled.md")])]),
            ])),
            .init(event: event(seq: 310, type: "turn/end", data: ["turn": .number(4)])),
        ]

        reducer.replaceWindow(entries, hasMore: false)
        let data = tryUnwrap(reducer.locationData(scope: .turn, turn: 4).value(for: "deliverables", as: CoreDeliverablesTurnData.self))
        XCTAssertEqual(data.paths(forClosingSequence: 303), ["out/index.html", "notes.md"])
        XCTAssertEqual(data.paths(), ["out/index.html", "notes.md", "out/app.css"])
        XCTAssertFalse(data.paths().contains("cancelled.md"))
        XCTAssertTrue(reducer.snapshot(target: "chat").allSatisfy { $0.kind != "deliverables" })
        XCTAssertNil(reducer.locationData(scope: .turn, turn: 99).value(for: "deliverables", as: CoreDeliverablesTurnData.self))
    }

    func testUnknownPluginToolCardDoesNotFabricateDeliverables() {
        let reducer = ConversationNodeReducer(definitions: ConversationCoreNodeRegistry.initialDefinitions())
        let entries: [ConversationEventInput] = [
            .init(event: event(seq: 400, type: "turn/start", data: ["turn": .number(8)])),
            .init(event: event(seq: 401, type: "tool/call", data: [
                "turn": .number(8), "callId": .string("future-card"), "name": .string("plugin_tool"), "arguments": .string("{\"fixture\":true}"),
            ]), view: toolView("call", [
                "card": .string("future-plugin-card"),
                "locations": .array([.object(["path": .string("must-not-be-produced.md")])]),
            ])),
            .init(event: toolResult(seq: 402, turn: 8, callID: "future-card")),
        ]

        XCTAssertEqual(reducer.replaceWindow(entries, hasMore: false), .immediate)
        let tool = tryUnwrap(reducer.snapshot(target: "chat").first(where: { $0.kind == "tool-call" })?.data as? CoreToolCallNode)
        XCTAssertEqual(tool.callID, "future-card")
        XCTAssertEqual(tool.name, "plugin_tool")
        XCTAssertEqual(tool.argumentsRaw, "{\"fixture\":true}")
        XCTAssertNil(reducer.locationData(scope: .turn, turn: 8).value(for: "deliverables", as: CoreDeliverablesTurnData.self))
    }

    private func toolResult(seq: Int, turn: Int, callID: String, isError: Bool = false) -> SessionEventDTO {
        event(seq: seq, type: "tool/result", surface: .string("append"), data: [
            "turn": .number(Double(turn)),
            "message": .object([
                "source": .object(["callId": .string(callID)]),
                "content": .array([.object(isError ? ["isError": .bool(true)] : [:])]),
            ]),
        ])
    }

    private func toolView(_ target: String, _ view: [String: JSONValue]) -> ToolEventViewDTO {
        .init(for: target, view: .object(view))
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
