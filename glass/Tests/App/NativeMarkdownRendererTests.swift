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

    func testSanitizerRemovesExecutableHTMLAndMakesUnsafeLinksInert() {
        let input = "<script>alert('x')</script><img src=x onerror=alert(1)> [local](file:///tmp/secret) [safe](https://example.com)"
        let sanitized = NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(input)

        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<script"))
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("onerror"))
        XCTAssertFalse(sanitized.contains("[local](file:"))
        XCTAssertTrue(sanitized.contains("local (file:///tmp/secret)"))
        XCTAssertTrue(sanitized.contains("[safe](https://example.com)"))
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
