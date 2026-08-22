import XCTest

@testable import GlassCore

final class NativeToolSearchViewAdapterTests: XCTestCase {
    func testAdapterAdmitsMatchesAndCardRetainsTruncatedTextRecoveryOnly() {
        let view = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("search"),
            "shape": .string("matches"),
            "title": .string("Grep preview"),
            "truncated": .bool(true),
            "total": .number(9),
            "files": .array([
                .object([
                    "path": .string("src/main.swift"),
                    "matches": .array([.object(["lineNumber": .number(7), "line": .string("needle")])]),
                ]),
            ]),
        ]))
        let admitted = try XCTUnwrap(view.nativeSearchView)
        XCTAssertEqual(admitted.title, "Grep preview")
        XCTAssertEqual(admitted.total, 9)
        XCTAssertEqual(admitted.shape, .matches([.init(path: "src/main.swift", matches: [.init(lineNumber: 7, line: "needle")])]))
        let card = try XCTUnwrap(NativeSearchCardPresentation.resolve(result: admitted, completed: true, textRecovery: "Full output stored at /tmp/search"))
        XCTAssertEqual(card.recovery, "Full output stored at /tmp/search")
        XCTAssertEqual(card.shownCount, 1)
        XCTAssertEqual(card.fileCount, 1)
        XCTAssertNil(NativeSearchCardPresentation.resolve(result: admitted, completed: false, textRecovery: "recovery"))

        let uncapped = NativeToolSearchView(title: nil, truncated: false, total: 1, shape: .paths(["README.md"]))
        XCTAssertNil(NativeSearchCardPresentation.resolve(result: uncapped, completed: true, textRecovery: "must not show")?.recovery)
    }

    func testRowsRepairTailHeaderWithoutExceedingCap() {
        let shape = NativeToolSearchView.Shape.matches([
            .init(path: "a.swift", matches: [.init(lineNumber: 1, line: "a1")]),
            .init(path: "b.swift", matches: [.init(lineNumber: 2, line: "b2"), .init(lineNumber: 3, line: "b3")]),
        ])
        let rows = NativeSearchRowsPresentation.resolve(shape: shape).rows
        XCTAssertEqual(rows.map(\.kind), [.file, .match, .file, .match, .match])
        let capped = NativeSearchWindowPresentation.resolve(rows: rows, maxLines: 3, expanded: false)
        XCTAssertEqual(capped.head.map(\.text), ["a.swift", "a1"])
        XCTAssertEqual(capped.tailHeader?.text, "b.swift")
        XCTAssertTrue(capped.tail.isEmpty)
        XCTAssertEqual(capped.hiddenCount, 2)
        XCTAssertEqual(capped.head.count + (capped.tailHeader == nil ? 0 : 1) + capped.tail.count, 3)
    }

    func testAdapterFailsClosedForUnknownAndMalformedSearchViews() {
        let unknown = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("search"), "shape": .string("semantic"), "truncated": .bool(false), "total": .number(0),
        ]))
        let malformedMatch = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("search"), "shape": .string("matches"), "truncated": .bool(false), "total": .number(1),
            "files": .array([.object(["path": .string("a.swift"), "matches": .array([.object(["lineNumber": .string("1"), "line": .string("bad")])])])]),
        ]))
        let malformedPaths = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("search"), "shape": .string("paths"), "truncated": .bool(false), "total": .number(1),
            "paths": .array([.number(1)]),
        ]))
        XCTAssertNil(unknown.nativeSearchView)
        XCTAssertNil(malformedMatch.nativeSearchView)
        XCTAssertNil(malformedPaths.nativeSearchView)
    }
}
