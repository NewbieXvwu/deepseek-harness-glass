import XCTest

@testable import GlassCore

final class NativeToolReadViewAdapterTests: XCTestCase {
    func testAdapterAdmitsCompleteReadResultAndPresentationUsesReplacementTitle() {
        let view = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("read"),
            "title": .string("README preview"),
            "path": .string("/workspace/README.md"),
            "lines": .array([
                .object(["number": .number(5), "text": .string("# Heading")]),
                .object(["number": .number(6), "text": .string("body")]),
            ]),
            "totalLines": .number(10),
            "lang": .string("markdown"),
        ]))
        let admitted = view.nativeReadView
        XCTAssertEqual(admitted?.path, "/workspace/README.md")
        XCTAssertEqual(admitted?.lines, [.init(number: 5, text: "# Heading"), .init(number: 6, text: "body")])
        XCTAssertEqual(admitted?.totalLines, 10)
        XCTAssertEqual(admitted?.lang, "markdown")
        XCTAssertEqual(
            NativeReadCardPresentation.resolve(result: admitted, completed: true),
            .init(label: "README preview", lines: [.init(number: 5, text: "# Heading"), .init(number: 6, text: "body")], totalLines: 10, lang: "markdown")
        )
    }

    func testReadWindowMatchesOfficialChatAndDetailsHeadTailCaps() {
        let lines = (1 ... 20).map { NativeToolReadLine(number: $0, text: "line-\($0)") }
        let chat = NativeReadCardWindowPresentation.resolve(lines: lines, maxLines: 8, expanded: false)
        XCTAssertEqual(chat.head.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(chat.tail.map(\.number), [17, 18, 19, 20])
        XCTAssertEqual(chat.hiddenCount, 12)

        let details = NativeReadCardWindowPresentation.resolve(lines: lines, maxLines: 16, expanded: false)
        XCTAssertEqual(details.head.map(\.number), Array(1 ... 8))
        XCTAssertEqual(details.tail.map(\.number), Array(13 ... 20))
        XCTAssertEqual(details.hiddenCount, 4)

        let expanded = NativeReadCardWindowPresentation.resolve(lines: lines, maxLines: 8, expanded: true)
        XCTAssertEqual(expanded.head, lines)
        XCTAssertTrue(expanded.tail.isEmpty)
        XCTAssertEqual(expanded.hiddenCount, 0)
    }

    func testAdapterAndPresentationFailClosedForRunningNonReadAndMalformedViews() {
        let generic = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("generic"),
            "path": .string("README.md"),
            "lines": .array([]),
            "totalLines": .number(0),
        ]))
        XCTAssertNil(generic.nativeReadView)

        let malformedLine = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("read"),
            "path": .string("README.md"),
            "lines": .array([.object(["number": .number(1.5), "text": .string("bad")])]),
            "totalLines": .number(1),
        ]))
        XCTAssertNil(malformedLine.nativeReadView)

        let malformedTotal = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("read"),
            "path": .string("README.md"),
            "lines": .array([.object(["number": .number(1), "text": .string("one")])]),
            "totalLines": .number(0),
        ]))
        XCTAssertNil(malformedTotal.nativeReadView)

        let outOfRangeLine = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("read"),
            "path": .string("README.md"),
            "lines": .array([.object(["number": .number(5), "text": .string("outside")])]),
            "totalLines": .number(4),
        ]))
        XCTAssertNil(outOfRangeLine.nativeReadView)

        let valid = NativeToolReadView(card: "read", title: nil, path: "README.md", lines: [], totalLines: 0, lang: nil)
        XCTAssertNil(NativeReadCardPresentation.resolve(result: valid, completed: false))
        XCTAssertNil(NativeReadCardPresentation.resolve(result: NativeToolReadView(card: "unknown", title: nil, path: "README.md", lines: [], totalLines: 0, lang: nil), completed: true))
        XCTAssertEqual(NativeReadCardPresentation.resolve(result: valid, completed: true)?.label, "README.md")
    }
}
