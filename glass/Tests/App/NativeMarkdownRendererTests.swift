import XCTest

@testable import GlassUI

final class NativeMarkdownRendererTests: XCTestCase {
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
