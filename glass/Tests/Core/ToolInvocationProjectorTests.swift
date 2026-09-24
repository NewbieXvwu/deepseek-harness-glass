import XCTest

@testable import GlassCore

final class ToolInvocationProjectorTests: XCTestCase {
    func testRawCallAndResultProjectTypedInvocation() throws {
        let projector = ToolInvocationProjector()
        let values = projector.replaceWindow([
            record(type: "tool/call", seq: 1, data: .object([
                "callId": .string("call-1"),
                "name": .string("bash"),
                "arguments": .string(#"{"command":"pwd","description":"Show cwd"}"#),
                "parentCallId": .string("parent-1"),
            ])),
            record(type: "tool/result", seq: 2, data: .object([
                "message": .object([
                    "source": .object(["callId": .string("call-1")]),
                    "content": .array([
                        .object([
                            "type": .string("tool-result"),
                            "toolCallId": .string("call-1"),
                            "content": .array([
                                .object(["type": .string("text"), "text": .string("line one")]),
                                .object(["type": .string("text"), "text": .string("line two")]),
                            ]),
                            "isError": .bool(false),
                        ]),
                    ]),
                ]),
                "meta": .object(["kind": .string("terminal")]),
            ])),
        ], sessionCWD: "/workspace")

        let invocation = try XCTUnwrap(values.first)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(invocation.id, "call-1")
        XCTAssertEqual(invocation.name, "bash")
        XCTAssertEqual(invocation.arguments, #"{"command":"pwd","description":"Show cwd"}"#)
        XCTAssertEqual(invocation.parentCallID, "parent-1")
        XCTAssertEqual(invocation.sessionCWD, "/workspace")
        XCTAssertEqual(invocation.state, .completed)
        XCTAssertEqual(invocation.output, "line one\nline two")
        XCTAssertEqual(invocation.textOutput, "line one\nline two")
        XCTAssertEqual(invocation.resultIsError, false)
        XCTAssertEqual(invocation.resultMeta?.objectValue?["kind"]?.stringValue, "terminal")
    }

    func testStructuredFailureAndInterruptedResultRemainHostDerived() throws {
        let projector = ToolInvocationProjector()
        _ = projector.replaceWindow([
            record(type: "tool/call", seq: 1, data: .object([
                "callId": .string("call-1"),
                "name": .string("bash"),
                "arguments": .string(#"{"command":"sleep 10","description":"Wait"}"#),
            ])),
        ], sessionCWD: nil)

        let values = projector.append(event(
            type: "tool/result",
            seq: 2,
            data: .object([
                "message": .object([
                    "source": .object(["callId": .string("call-1")]),
                ]),
                "error": .object([
                    "name": .string("ToolError"),
                    "code": .string("interrupted"),
                ]),
            ])
        ), sessionCWD: nil)

        let invocation = try XCTUnwrap(values.first)
        XCTAssertEqual(invocation.state, .stopped)
        XCTAssertEqual(invocation.errorName, "ToolError")
        XCTAssertEqual(invocation.errorCode, "interrupted")
        XCTAssertEqual(invocation.resultIsError, true)
        XCTAssertEqual(invocation.output, "ToolError: interrupted")
        XCTAssertNil(invocation.textOutput)
    }

    func testWholeWindowReplacementDropsPriorCallsAndUnmatchedResultCannotCreateAuthority() {
        let projector = ToolInvocationProjector()
        _ = projector.replaceWindow([
            record(type: "tool/call", seq: 1, data: .object([
                "callId": .string("old"),
                "name": .string("read"),
                "arguments": .string(#"{"file_path":"old"}"#),
            ])),
        ], sessionCWD: "/old")

        let values = projector.replaceWindow([
            record(type: "tool/result", seq: 10, data: .object([
                "message": .object([
                    "source": .object(["callId": .string("missing")]),
                ]),
            ])),
            record(type: "tool/call", seq: 11, data: .object([
                "callId": .string("fresh"),
                "name": .string("read"),
                "arguments": .string(#"{"file_path":"fresh"}"#),
            ])),
        ], sessionCWD: "/fresh")

        XCTAssertEqual(values.map { $0.id }, ["fresh"])
        XCTAssertEqual(values.first?.state, .running)
        XCTAssertEqual(values.first?.sessionCWD, "/fresh")
    }

    private func record(
        type: String,
        seq: Int,
        data: RemoteJSONValue
    ) -> RemoteSessionHistoryRecord {
        .event(event(type: type, seq: seq, data: data))
    }

    private func event(
        type: String,
        seq: Int,
        data: RemoteJSONValue
    ) -> RemoteSessionWireEvent {
        .init(
            type: type,
            seq: SessionSeq(rawValue: seq),
            time: Int64(seq),
            data: data,
            ignorable: nil,
            sourceEventSeqs: nil,
            surfaceOp: nil
        )
    }
}
