import XCTest

@testable import GlassCore

final class SessionProjectionIncrementalTests: XCTestCase {
    private let generation = RemoteConnectionGeneration(rawValue: 41)
    private let address = SessionAddress.session(sessionID: "incremental")

    func testJournalRevisionDescribesReplaceAppendPrependAndNoop() throws {
        var journal = SessionJournal()
        try journal.open(
            generation: generation,
            address: address,
            frame: opening(cursor: 2, records: [record(type: "turn/start", seq: 2, data: .object(["turn": .number(1)]))], hasMore: true)
        )

        let opened = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(opened.revision, 1)
        XCTAssertEqual(opened.mutation, .authoritativeReplace)

        XCTAssertTrue(try journal.append(
            generation: generation,
            event: event(type: "assistant/chunk", seq: 3, data: .object(["turn": .number(1), "step": .number(1)]))
        ))
        let appended = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(appended.revision, 2)
        XCTAssertEqual(appended.mutation, .append(startRecordIndex: 1))

        XCTAssertEqual(try journal.prepend(
            generation: generation,
            page: .init(records: [record(type: "user/message", seq: 1, data: userMessageData(id: "older"), surfaceOp: .string("append"))], hasMore: false)
        ), 1)
        let prepended = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(prepended.revision, 3)
        XCTAssertEqual(prepended.mutation, .prepend(acceptedRecordCount: 1))

        XCTAssertEqual(try journal.prepend(
            generation: generation,
            page: .init(records: [], hasMore: false)
        ), 0)
        XCTAssertEqual(journal.snapshot?.revision, 3)
        XCTAssertEqual(journal.snapshot?.mutation, .prepend(acceptedRecordCount: 1))
    }

    func testFoldPlanSkipsSameRevisionUsesAdjacentAppendAndRefoldsMissedOrStructuralChanges() throws {
        var journal = SessionJournal()
        try journal.open(
            generation: generation,
            address: address,
            frame: opening(cursor: 2, records: [record(type: "turn/start", seq: 2, data: .object(["turn": .number(1)]))], hasMore: true)
        )
        let opened = try XCTUnwrap(journal.snapshot)
        let openedCursor = SessionProjectionEngine.JournalFoldCursor(opened)
        XCTAssertEqual(
            SessionProjectionEngine.journalFoldPlan(previous: openedCursor, journal: opened),
            .unchanged
        )

        _ = try journal.append(
            generation: generation,
            event: event(type: "assistant/chunk", seq: 3, data: .object(["turn": .number(1), "step": .number(1)]))
        )
        let oneAppend = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(
            SessionProjectionEngine.journalFoldPlan(previous: openedCursor, journal: oneAppend),
            .append(startRecordIndex: 1)
        )

        _ = try journal.append(
            generation: generation,
            event: event(type: "turn/end", seq: 4, data: .object(["turn": .number(1)]))
        )
        let missedAppend = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(
            SessionProjectionEngine.journalFoldPlan(previous: openedCursor, journal: missedAppend),
            .replace
        )

        let beforePrepend = SessionProjectionEngine.JournalFoldCursor(missedAppend)
        _ = try journal.prepend(
            generation: generation,
            page: .init(records: [record(type: "user/message", seq: 1, data: userMessageData(id: "older"), surfaceOp: .string("append"))], hasMore: false)
        )
        let prepended = try XCTUnwrap(journal.snapshot)
        XCTAssertEqual(
            SessionProjectionEngine.journalFoldPlan(previous: beforePrepend, journal: prepended),
            .replace
        )
    }

    func testRevisionZeroFixturesAlwaysRefold() {
        let fixture = SessionJournalSnapshot(
            generation: generation,
            address: address,
            header: header(),
            openingCut: SessionSeq(rawValue: 1),
            records: [record(type: "user/message", seq: 1, data: userMessageData(id: "fixture"), surfaceOp: .string("append"))],
            hasMore: false,
            projections: .init(asOfSeq: SessionSeq(rawValue: 1), values: [:]),
            appliedThrough: SessionSeq(rawValue: 1)
        )
        XCTAssertEqual(fixture.revision, 0)
        XCTAssertEqual(
            SessionProjectionEngine.journalFoldPlan(
                previous: SessionProjectionEngine.JournalFoldCursor(fixture),
                journal: fixture
            ),
            .replace
        )
    }

    func testIncrementalToolAndConversationFoldMatchesFreshFullProjection() throws {
        var journal = SessionJournal()
        try journal.open(
            generation: generation,
            address: address,
            frame: opening(
                cursor: 2,
                records: [
                    record(type: "user/message", seq: 1, data: userMessageData(id: "message-1"), surfaceOp: .string("append")),
                    record(type: "turn/start", seq: 2, data: .object(["turn": .number(1)])),
                ],
                hasMore: false
            )
        )

        let incremental = SessionProjectionEngine()
        var projected = incremental.project(.init(journal: try XCTUnwrap(journal.snapshot), control: nil))
        XCTAssertTrue(projected.isRunning)

        for next in [
            event(type: "tool/call", seq: 3, data: .object([
                "callId": .string("call-1"),
                "name": .string("read"),
                "arguments": .string(#"{"file_path":"README.md"}"#),
                "turn": .number(1),
                "step": .number(1),
            ])),
            event(type: "tool/result", seq: 4, data: .object([
                "message": .object([
                    "source": .object(["callId": .string("call-1")]),
                    "content": .array([.object([
                        "type": .string("tool-result"),
                        "toolCallId": .string("call-1"),
                        "content": .array([.object(["type": .string("text"), "text": .string("done")])]),
                        "isError": .bool(false),
                    ])]),
                ]),
            ])),
            event(type: "turn/end", seq: 5, data: .object(["turn": .number(1)])),
        ] {
            XCTAssertTrue(try journal.append(generation: generation, event: next))
            projected = incremental.project(.init(journal: try XCTUnwrap(journal.snapshot), control: nil))
        }

        let finalJournal = try XCTUnwrap(journal.snapshot)
        let fresh = SessionProjectionEngine().project(.init(journal: finalJournal, control: nil))
        XCTAssertEqual(projected.chatNodes.map(\.key), fresh.chatNodes.map(\.key))
        XCTAssertEqual(projected.chatNodes.map(\.kind), fresh.chatNodes.map(\.kind))
        XCTAssertEqual(projected.trajectoryNodes.map(\.key), fresh.trajectoryNodes.map(\.key))
        XCTAssertEqual(projected.toolInvocations.map(\.id), fresh.toolInvocations.map(\.id))
        XCTAssertEqual(projected.toolInvocations.first?.state, .completed)
        XCTAssertEqual(projected.toolInvocations.first?.output, "done")
        XCTAssertEqual(projected.toolInvocations.first?.sessionCWD, "/workspace")
        XCTAssertEqual(projected.isRunning, fresh.isRunning)
        XCTAssertFalse(projected.isRunning)
    }

    func testControlOnlyPublicationKeepsDurableFoldCursorAndPublishesNewControlAuthority() throws {
        var journal = SessionJournal()
        try journal.open(
            generation: generation,
            address: address,
            frame: opening(
                cursor: 1,
                records: [record(type: "user/message", seq: 1, data: userMessageData(id: "message-1"), surfaceOp: .string("append"))],
                hasMore: false
            )
        )
        let durable = try XCTUnwrap(journal.snapshot)
        let engine = SessionProjectionEngine()
        let first = engine.project(.init(
            journal: durable,
            control: .init(
                generation: generation,
                queue: [],
                jobs: [],
                projections: modelBaseline(seq: 10, model: "model-a")
            )
        ))
        let second = engine.project(.init(
            journal: durable,
            control: .init(
                generation: generation,
                queue: [],
                jobs: [],
                projections: modelBaseline(seq: 11, model: "model-b")
            )
        ))

        XCTAssertEqual(first.chatNodes.map(\.key), second.chatNodes.map(\.key))
        XCTAssertEqual(first.modelSelection?.model, "model-a")
        XCTAssertEqual(second.modelSelection?.model, "model-b")
        XCTAssertEqual(second.projectionSequence, SessionSeq(rawValue: 11))
        XCTAssertEqual(
            SessionProjectionEngine.journalFoldPlan(
                previous: SessionProjectionEngine.JournalFoldCursor(durable),
                journal: durable
            ),
            .unchanged
        )
    }

    func testTenThousandLiveChunksStayOnIncrementalEnginePath() throws {
        var journal = SessionJournal()
        try journal.open(
            generation: generation,
            address: address,
            frame: opening(
                cursor: 1,
                records: [record(type: "step/start", seq: 1, data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                ]))],
                hasMore: false
            )
        )
        let engine = SessionProjectionEngine()
        _ = engine.project(.init(journal: try XCTUnwrap(journal.snapshot), control: nil))

        var projected: SessionProjectionEngine.Snapshot?
        for index in 1 ... 10_000 {
            let seq = index + 1
            _ = try journal.append(
                generation: generation,
                event: event(type: "assistant/chunk", seq: seq, data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "chunk": .object([
                        "type": .string("text-delta"),
                        "index": .number(0),
                        "text": .string("x"),
                    ]),
                ]))
            )
            projected = engine.project(.init(journal: try XCTUnwrap(journal.snapshot), control: nil))
        }

        let final = try XCTUnwrap(projected)
        let assistant = try XCTUnwrap(final.chatNodes.first(where: { $0.kind == "assistant-step" })?.data as? CoreAssistantNode)
        XCTAssertEqual(final.chatNodes.filter { $0.kind == "assistant-step" }.count, 1)
        XCTAssertEqual(assistant.blocks.first?.text?.count, 10_000)
        XCTAssertEqual(journal.snapshot?.revision, 10_001)
        XCTAssertEqual(journal.snapshot?.mutation, .append(startRecordIndex: 10_000))
    }

    private func opening(
        cursor: Int,
        records: [RemoteSessionHistoryRecord],
        hasMore: Bool
    ) -> RemoteSessionFollowFrame {
        .snapshot(
            header: header(),
            cursor: SessionSeq(rawValue: cursor),
            records: records,
            hasMore: hasMore,
            projections: .init(asOfSeq: SessionSeq(rawValue: cursor), values: [:])
        )
    }

    private func header() -> RemoteSessionWireHeader {
        .init(
            version: 1,
            id: "incremental",
            createdAt: 1,
            cwd: "/workspace",
            parentSession: nil,
            seedLength: nil,
            origin: nil,
            delegationDepth: nil,
            agentPreset: nil
        )
    }

    private func record(
        type: String,
        seq: Int,
        data: RemoteJSONValue,
        surfaceOp: RemoteJSONValue? = nil
    ) -> RemoteSessionHistoryRecord {
        .event(event(type: type, seq: seq, data: data, surfaceOp: surfaceOp))
    }

    private func event(
        type: String,
        seq: Int,
        data: RemoteJSONValue,
        surfaceOp: RemoteJSONValue? = nil
    ) -> RemoteSessionWireEvent {
        .init(
            type: type,
            seq: SessionSeq(rawValue: seq),
            time: Int64(seq),
            data: data,
            ignorable: nil,
            sourceEventSeqs: nil,
            surfaceOp: surfaceOp
        )
    }

    private func userMessageData(id: String) -> RemoteJSONValue {
        .object([
            "id": .string(id),
            "content": .array([.object(["type": .string("text"), "text": .string(id)])]),
            "source": .object(["kind": .string("user")]),
        ])
    }

    private func modelBaseline(seq: Int, model: String) -> RemoteSessionProjectionBaseline {
        .init(
            asOfSeq: SessionSeq(rawValue: seq),
            values: [
                "model/selection": .object([
                    "next": .object([
                        "provider": .string("provider"),
                        "model": .string(model),
                    ]),
                ]),
            ]
        )
    }
}
