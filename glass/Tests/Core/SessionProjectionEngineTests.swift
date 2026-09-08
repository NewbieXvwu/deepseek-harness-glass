import XCTest

@testable import GlassCore

final class SessionProjectionEngineTests: XCTestCase {
    func testCompleteRuntimeStateFoldsConversationAndCurrentControlAuthority() {
        let generation = RemoteConnectionGeneration(rawValue: 7)
        let address = SessionAddress.session(sessionID: "session-a")
        let journalBaseline = RemoteSessionProjectionBaseline(
            asOfSeq: SessionSeq(rawValue: 2),
            values: ["journal-only": .string("durable")]
        )
        let journal = SessionJournalSnapshot(
            generation: generation,
            address: address,
            header: .init(
                version: 1,
                id: "session-a",
                createdAt: 1,
                cwd: "/workspace",
                parentSession: nil,
                seedLength: nil,
                origin: nil,
                delegationDepth: nil,
                agentPreset: nil
            ),
            openingCut: SessionSeq(rawValue: 2),
            records: [
                .event(Self.event(
                    type: "user/message",
                    seq: 1,
                    data: .object([
                        "id": .string("message-1"),
                        "content": .array([.object(["type": .string("text"), "text": .string("hello")])]),
                        "source": .object(["kind": .string("user")]),
                    ]),
                    surfaceOp: .string("append")
                )),
                .event(Self.event(
                    type: "turn/start",
                    seq: 2,
                    data: .object(["turn": .number(1)])
                )),
            ],
            hasMore: true,
            projections: journalBaseline,
            appliedThrough: SessionSeq(rawValue: 2)
        )
        let controlBaseline = RemoteSessionProjectionBaseline(
            asOfSeq: SessionSeq(rawValue: 3),
            values: [
                "model/selection": .object([
                    "next": .object([
                        "provider": .string("provider-a"),
                        "model": .string("model-a"),
                        "reasoningEffort": .string("high"),
                    ]),
                ]),
            ]
        )
        let queued = RemoteSessionQueuedItem(
            id: "queue-1",
            placement: .queued,
            rpcId: nil,
            message: .init(id: "queued-message", content: [.string("queued")])
        )
        let job = RemoteSessionJob(
            id: "job-1",
            kind: "bash",
            label: "Build",
            status: .running,
            detail: nil,
            startedAt: 10,
            finishedAt: nil
        )
        let state = SessionRuntimeState(
            journal: journal,
            control: .init(
                generation: generation,
                queue: [queued],
                jobs: [job],
                projections: controlBaseline
            )
        )

        let projection = SessionProjectionEngine().project(state)

        XCTAssertEqual(projection.generation, generation)
        XCTAssertEqual(projection.address, address)
        XCTAssertEqual(projection.chatNodes.map { $0.kind }, ["user"])
        XCTAssertEqual((projection.chatNodes.first?.data as? CoreUserMessageNode)?.messageID, "message-1")
        XCTAssertEqual(projection.trajectoryNodes.map { $0.kind }, ["trajectory-input-message"])
        XCTAssertTrue(projection.toolCalls.isEmpty)
        XCTAssertTrue(projection.toolInvocations.isEmpty)
        XCTAssertEqual(projection.queue, [queued])
        XCTAssertEqual(projection.jobs, [job])
        XCTAssertEqual(projection.projectionSequence, SessionSeq(rawValue: 3))
        XCTAssertNil(projection.projectionValues["journal-only"])
        XCTAssertEqual(
            projection.modelSelection,
            RemoteModelSelection(provider: "provider-a", model: "model-a", reasoningEffort: "high")
        )
        XCTAssertTrue(projection.isRunning)
        XCTAssertTrue(projection.hasMoreHistory)
    }

    func testRawToolProjectionIsEngineOwnedAndRefoldsWithJournalAuthority() throws {
        let generation = RemoteConnectionGeneration(rawValue: 9)
        let engine = SessionProjectionEngine()
        let baseline = RemoteSessionProjectionBaseline(asOfSeq: SessionSeq(rawValue: 2), values: [:])
        let toolState = SessionRuntimeState(
            journal: .init(
                generation: generation,
                address: .session(sessionID: "tools"),
                header: .init(
                    version: 1, id: "tools", createdAt: 1, cwd: "/workspace",
                    parentSession: nil, seedLength: nil, origin: nil, delegationDepth: nil, agentPreset: nil
                ),
                openingCut: SessionSeq(rawValue: 2),
                records: [
                    .event(Self.event(
                        type: "tool/call",
                        seq: 1,
                        data: .object([
                            "callId": .string("call-1"),
                            "name": .string("read"),
                            "arguments": .string(#"{"file_path":"README.md"}"#),
                        ])
                    )),
                    .event(Self.event(
                        type: "tool/result",
                        seq: 2,
                        data: .object([
                            "message": .object([
                                "source": .object(["callId": .string("call-1")]),
                                "content": .array([.object([
                                    "type": .string("tool-result"),
                                    "toolCallId": .string("call-1"),
                                    "content": .array([.object(["type": .string("text"), "text": .string("done")])]),
                                    "isError": .bool(false),
                                ])]),
                            ]),
                        ])
                    )),
                ],
                hasMore: false,
                projections: baseline,
                appliedThrough: SessionSeq(rawValue: 2)
            ),
            control: nil
        )

        let projected = engine.project(toolState)
        let invocation = try XCTUnwrap(projected.toolInvocations.first)
        XCTAssertEqual(projected.toolInvocations.count, 1)
        XCTAssertEqual(invocation.id, "call-1")
        XCTAssertEqual(invocation.name, "read")
        XCTAssertEqual(invocation.state, .completed)
        XCTAssertEqual(invocation.output, "done")
        XCTAssertEqual(invocation.sessionCWD, "/workspace")

        let fresh = engine.project(Self.state(
            generation: generation, sessionID: "fresh", messageID: "m", text: "fresh", projectionValue: "fresh"
        ))
        XCTAssertTrue(fresh.toolInvocations.isEmpty)
    }

    func testCompleteStateRefoldDropsPriorConversationAndFallsBackToJournalProjectionCut() {
        let generation = RemoteConnectionGeneration(rawValue: 8)
        let engine = SessionProjectionEngine()
        let first = Self.state(
            generation: generation,
            sessionID: "first",
            messageID: "old",
            text: "old authority",
            projectionValue: "old"
        )
        _ = engine.project(first)

        let second = Self.state(
            generation: generation,
            sessionID: "second",
            messageID: "fresh",
            text: "fresh authority",
            projectionValue: "fresh"
        )
        let reused = engine.project(second)
        let fresh = SessionProjectionEngine().project(second)

        XCTAssertEqual(reused.chatNodes.map { $0.key }, fresh.chatNodes.map { $0.key })
        XCTAssertEqual(reused.chatNodes.map { $0.kind }, fresh.chatNodes.map { $0.kind })
        XCTAssertEqual((reused.chatNodes.first?.data as? CoreUserMessageNode)?.messageID, "fresh")
        XCTAssertEqual(reused.projectionValues["title"], .string("fresh"))
        XCTAssertEqual(reused.projectionSequence, SessionSeq(rawValue: 1))
        XCTAssertTrue(reused.queue.isEmpty)
        XCTAssertTrue(reused.jobs.isEmpty)
        XCTAssertFalse(reused.isRunning)
    }

    private static func state(
        generation: RemoteConnectionGeneration,
        sessionID: String,
        messageID: String,
        text: String,
        projectionValue: String
    ) -> SessionRuntimeState {
        let record = RemoteSessionHistoryRecord.event(event(
            type: "user/message",
            seq: 1,
            data: .object([
                "id": .string(messageID),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                "source": .object(["kind": .string("user")]),
            ]),
            surfaceOp: .string("append")
        ))
        let baseline = RemoteSessionProjectionBaseline(
            asOfSeq: SessionSeq(rawValue: 1),
            values: ["title": .string(projectionValue)]
        )
        return .init(
            journal: .init(
                generation: generation,
                address: .session(sessionID: sessionID),
                header: .init(
                    version: 1,
                    id: sessionID,
                    createdAt: 1,
                    cwd: nil,
                    parentSession: nil,
                    seedLength: nil,
                    origin: nil,
                    delegationDepth: nil,
                    agentPreset: nil
                ),
                openingCut: SessionSeq(rawValue: 1),
                records: [record],
                hasMore: false,
                projections: baseline,
                appliedThrough: SessionSeq(rawValue: 1)
            ),
            control: nil
        )
    }

    private static func event(
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
}
