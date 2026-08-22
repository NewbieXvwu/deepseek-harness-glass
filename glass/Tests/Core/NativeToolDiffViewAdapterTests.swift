import XCTest

@testable import GlassCore

final class NativeToolDiffViewAdapterTests: XCTestCase {
    func testAdapterAdmitsTypedHunksAndSettledResultReplacesCallIntent() {
        let call = ToolEventViewDTO(for: "call", view: .object([
            "card": .string("diff"),
            "diffs": .array([.object([
                "path": .string("draft.txt"), "oldText": .string("before"), "newText": .string("intent"),
            ])]),
        ]))
        let result = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("diff"),
            "diffs": .array([.object([
                "path": .string("draft.txt"), "oldText": .string("before"), "newText": .string("applied"),
            ])]),
        ]))
        XCTAssertEqual(NativeDiffCardPresentation.resolve(call: call.nativeDiffView, result: nil, settled: false)?.source, .call)
        XCTAssertEqual(NativeDiffCardPresentation.resolve(call: call.nativeDiffView, result: result.nativeDiffView, settled: true)?.source, .result)
        XCTAssertEqual(NativeDiffCardPresentation.resolve(call: call.nativeDiffView, result: result.nativeDiffView, settled: true)?.diffs.first?.newText, "applied")
        XCTAssertEqual(NativeDiffCardPresentation.resolve(call: nil, result: result.nativeDiffView, settled: true)?.source, .result)
    }

    func testRowsPreserveTerminatorBlankAndSamePathContracts() {
        let rows = NativeDiffRowsPresentation.resolve(diffs: [
            .init(path: "a.swift", oldText: "old\n", newText: "new\n\n"),
            .init(path: "a.swift", oldText: nil, newText: "second"),
            .init(path: "b.swift", oldText: "", newText: "created"),
        ])
        XCTAssertEqual(
            rows.rows,
            [
                .init(kind: .path, text: "a.swift"),
                .init(kind: .deletion, text: "old"),
                .init(kind: .addition, text: "new"),
                .init(kind: .addition, text: ""),
                .init(kind: .gap, text: "⋯"),
                .init(kind: .addition, text: "second"),
                .init(kind: .path, text: "b.swift"),
                .init(kind: .addition, text: "created"),
            ]
        )
        XCTAssertEqual(rows.added, 4)
        XCTAssertEqual(rows.removed, 1)
        XCTAssertEqual(rows.files, 2)
    }

    func testMalformedOrGenericDiffViewsFailClosed() {
        let missingOld = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("diff"),
            "diffs": .array([.object(["path": .string("a.swift"), "newText": .string("after")])]),
        ]))
        let invalidOld = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("diff"),
            "diffs": .array([.object(["path": .string("a.swift"), "oldText": .number(1), "newText": .string("after")])]),
        ]))
        let empty = ToolEventViewDTO(for: "result", view: .object(["card": .string("diff"), "diffs": .array([])]))
        let generic = ToolEventViewDTO(for: "result", view: .object(["card": .string("generic")]))
        XCTAssertNil(missingOld.nativeDiffView)
        XCTAssertNil(invalidOld.nativeDiffView)
        XCTAssertNil(empty.nativeDiffView)
        XCTAssertNil(generic.nativeDiffView)
        XCTAssertNil(NativeDiffCardPresentation.resolve(call: nil, result: nil, settled: true))
    }
}
