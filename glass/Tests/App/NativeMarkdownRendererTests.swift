import XCTest

@testable import GlassUI

final class NativeMarkdownRendererTests: XCTestCase {
    func testRC1WideTablePresentationStartsAtFourColumns() {
        XCTAssertFalse(NativeMarkdownTablePresentation.isWide(columnCount: 0))
        XCTAssertFalse(NativeMarkdownTablePresentation.isWide(columnCount: 3))
        XCTAssertTrue(NativeMarkdownTablePresentation.isWide(columnCount: 4))
        XCTAssertTrue(NativeMarkdownTablePresentation.isWide(columnCount: 8))
    }

    func testOnlyAbsoluteHTTPURLsPassExternalDestinationPolicy() {
        XCTAssertEqual(NativeMarkdownSecurityPolicy.externalURL(from: "https://example.com/docs")?.absoluteString, "https://example.com/docs")
        XCTAssertEqual(NativeMarkdownSecurityPolicy.externalURL(from: "HTTP://example.com/path")?.scheme?.lowercased(), "http")

        for unsafe in ["file:///Users/private/secret.txt", "javascript:alert(1)", "data:text/html,boom", "../relative", "/absolute-but-not-url", "mailto:test@example.com"] {
            XCTAssertNil(NativeMarkdownSecurityPolicy.externalURL(from: unsafe), "unsafe destination unexpectedly allowed: \(unsafe)")
        }
    }

    func testExternalURLRouterOpensOnlyHTTPDestinations() {
        var opened: [URL] = []
        XCTAssertTrue(NativeMarkdownSecurityPolicy.openExternal(URL(string: "https://example.com/safe")!) { opened.append($0) })
        XCTAssertEqual(opened.map(\.absoluteString), ["https://example.com/safe"])

        for unsafe in ["file:///tmp/private", "data:text/html,boom", "javascript:alert(1)"] {
            XCTAssertFalse(NativeMarkdownSecurityPolicy.openExternal(URL(string: unsafe)!) { opened.append($0) })
        }
        XCTAssertEqual(opened.map(\.absoluteString), ["https://example.com/safe"])
    }

    func testSanitizerRemovesExecutableHTMLAndMakesUnsafeLinksInert() {
        let input = "<script>alert('x')</script><img src=x onerror=alert(1)> [local](file:///tmp/secret) [safe](https://example.com)"
        let sanitized = NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(input)

        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<script"))
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("onerror"))
        XCTAssertFalse(sanitized.contains("[local](file:"))
        XCTAssertTrue(sanitized.contains("local (file:///tmp/secret)"))
        XCTAssertTrue(sanitized.contains("[safe](https://example.com)"))

        let comment = "before <!-- [smuggled](file:///tmp/secret) --> after"
        let withoutComment = NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(comment)
        XCTAssertEqual(withoutComment, "before  after")
    }

    func testStreamingSanitizerIsDeterministicAndNeverActivatesUnsafeLinkPrefixes() {
        let chunks = [
            "before <script>ignored",
            "()</script> [unsafe](file:///tmp/secret)",
            " [safe](https://example.com/docs) <img src=x onerror=alert(1)> after",
        ]
        var streamed = ""
        for chunk in chunks {
            streamed += chunk
            let once = NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(streamed)
            XCTAssertEqual(once, NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(streamed))
            let activeLinks = NativeMarkdownSecurityPolicy.attributedInlineMarkdown(streamed).runs.compactMap { $0.link?.absoluteString }
            XCTAssertFalse(activeLinks.contains(where: { $0.hasPrefix("file:") || $0.hasPrefix("javascript:") || $0.hasPrefix("data:") }))
        }

        let settled = NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(streamed)
        XCTAssertFalse(settled.localizedCaseInsensitiveContains("<script"))
        XCTAssertFalse(settled.localizedCaseInsensitiveContains("onerror"))
        XCTAssertTrue(settled.contains("unsafe (file:///tmp/secret)"))
        XCTAssertTrue(settled.contains("[safe](https://example.com/docs)"))
    }

    func testRenderedAttributedMarkdownRetainsOnlyHTTPLinkAttributes() {
        let attributed = NativeMarkdownSecurityPolicy.attributedInlineMarkdown(
            "[safe](https://example.com) [file](file:///tmp/private) <javascript:alert(1)>"
        )
        let links = attributed.runs.compactMap { $0.link?.absoluteString }

        XCTAssertEqual(links, ["https://example.com"])
    }

    func testNativeHighlighterClassifiesSupportedLanguageAndKeepsUnknownLanguagePlain() {
        let swift = NativeCodeHighlighter.fragments(code: "let value = \"safe\" // comment", language: "swift")
        XCTAssertEqual(swift, [
            .init(text: "let", kind: .keyword),
            .init(text: " value = ", kind: .plain),
            .init(text: "\"safe\"", kind: .string),
            .init(text: " ", kind: .plain),
            .init(text: "// comment", kind: .comment),
        ])
        XCTAssertEqual(
            NativeCodeHighlighter.fragments(code: "<script>alert(1)</script>", language: "untrusted"),
            [.init(text: "<script>alert(1)</script>", kind: .plain)]
        )
    }

    func testHighlighterPreservesLongCodeInputAndUnknownLanguagesRemainSinglePlainRun() {
        let code = (0..<1_000).map { "let value\($0) = \($0) // line \($0)" }.joined(separator: "\n")
        let highlighted = NativeCodeHighlighter.fragments(code: code, language: "swift")
        XCTAssertEqual(highlighted.map(\.text).joined(), code)
        XCTAssertFalse(highlighted.isEmpty)

        let unknown = NativeCodeHighlighter.fragments(code: code, language: "unregistered-language")
        XCTAssertEqual(unknown, [.init(text: code, kind: .plain)])
    }

    func testLongMarkdownAndCodePerformanceBaselinePreservesContent() {
        let code = (0 ..< 2_000).map { "let value\($0) = \($0) // line \($0)" }.joined(separator: "\n")
        let markdown = "# Fixture\n\n```swift\n\(code)\n```\n\n" + (0 ..< 200).map { "- [safe](https://example.com/\($0))" }.joined(separator: "\n")
        measure(metrics: [XCTClockMetric()]) {
            let blocks = NativeMarkdownDocument.parse(markdown)
            let renderedCode = NativeCodeHighlighter.fragments(code: code, language: "swift").map(\.text).joined()
            XCTAssertEqual(renderedCode, code)
            XCTAssertTrue(blocks.contains { block in
                if case let .code(_, language, rendered) = block { return language == "swift" && rendered == code }
                return false
            })
        }
    }

    func testQuoteAndListsBecomeStableNativeBlocksWithoutUnsafeLinkActivation() {
        let blocks = NativeMarkdownDocument.parse(
            "intro\n> quoted [safe](https://example.com)\n> `file:///private`\n- first\n- [unsafe](file:///tmp/private)\n1. ordered\n2. second\nafter"
        )
        XCTAssertEqual(blocks, [
            .prose(id: 0, text: "intro"),
            .quote(id: 1, text: "quoted [safe](https://example.com)\n`file:///private`"),
            .list(id: 2, ordered: false, items: ["first", "[unsafe](file:///tmp/private)"]),
            .list(id: 3, ordered: true, items: ["ordered", "second"]),
            .prose(id: 4, text: "after"),
        ])

        let unsafeListItem = NativeMarkdownSecurityPolicy.attributedInlineMarkdown("[unsafe](file:///tmp/private)")
        XCTAssertTrue(unsafeListItem.runs.allSatisfy { $0.link == nil })
    }

    func testGFMTableUsesASTCellsAndKeepsUnsafeLinksInert() {
        let blocks = NativeMarkdownDocument.parse(
            "| Language | Documentation |\n| --- | --- |\n| Swift | [Safe](https://swift.org) |\n| Local | [Unsafe](file:///tmp/private) |"
        )

        XCTAssertEqual(blocks, [
            .table(
                id: 0,
                header: ["Language", "Documentation"],
                rows: [
                    ["Swift", "[Safe](https://swift.org)"],
                    ["Local", "[Unsafe](file:///tmp/private)"],
                ]
            ),
        ])
        let unsafeCell = NativeMarkdownSecurityPolicy.attributedInlineMarkdown("[Unsafe](file:///tmp/private)")
        XCTAssertTrue(unsafeCell.runs.allSatisfy { $0.link == nil })
    }

    func testFencedCodeHasStableCodeBlockAndIncompleteFenceStaysLiteralProse() {
        let settled = NativeMarkdownDocument.parse("before\n```swift\nlet x = 1\n```\nafter")
        XCTAssertEqual(settled, [
            .prose(id: 0, text: "before"),
            .code(id: 1, language: "swift", code: "let x = 1"),
            .prose(id: 2, text: "after"),
        ])

        let streaming = NativeMarkdownDocument.parse("before\n```swift\nlet x = 1")
        XCTAssertEqual(streaming, [
            .prose(id: 0, text: "before"),
            .prose(id: 1, text: "```swift\nlet x = 1"),
        ])
    }
}
