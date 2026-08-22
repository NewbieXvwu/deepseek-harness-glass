import XCTest

@testable import GlassCore

final class NativeToolWebViewAdapterTests: XCTestCase {
    func testAdapterAdmitsSearchAndFetchResultsOnly() throws {
        let search = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("web"), "kind": .string("search"), "truncated": .bool(true),
            "answer": .string("A sourced answer"),
            "sources": .array([.object([
                "url": .string("https://example.com/article"), "title": .string("Example"),
                "snippet": .string("excerpt"), "publishedAt": .string("2026-08-22"),
            ])]),
        ]))
        let admitted = try XCTUnwrap(search.nativeWebView)
        guard case let .search(answer, sources, truncated) = admitted.kind else {
            return XCTFail("expected search")
        }
        XCTAssertEqual(answer, "A sourced answer")
        XCTAssertEqual(sources, [.init(url: "https://example.com/article", title: "Example", snippet: "excerpt", publishedAt: "2026-08-22")])
        XCTAssertTrue(truncated)
        XCTAssertNotNil(NativeWebCardPresentation.resolve(result: admitted, completed: true))
        XCTAssertNil(NativeWebCardPresentation.resolve(result: admitted, completed: false))

        let fetch = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("web"), "kind": .string("fetch"), "truncated": .bool(false),
            "url": .string("https://example.com/final"), "statusCode": .number(200),
        ]))
        guard case let .fetch(url, statusCode, truncated)? = fetch.nativeWebView?.kind else {
            return XCTFail("expected fetch")
        }
        XCTAssertEqual(url, "https://example.com/final")
        XCTAssertEqual(statusCode, 200)
        XCTAssertFalse(truncated)
    }

    func testSafeWebLinkAllowsOnlyHTTPAndHTTPSAndHasNonemptyLabel() {
        let titled = NativeSafeWebLink.resolve(url: "https://example.com/article", title: "Article")
        XCTAssertEqual(titled.label, "Article")
        XCTAssertEqual(titled.destination?.absoluteString, "https://example.com/article")
        XCTAssertEqual(NativeSafeWebLink.resolve(url: "https://example.com/article", title: nil).label, "example.com")
        XCTAssertNil(NativeSafeWebLink.resolve(url: "javascript:alert(1)", title: nil).destination)
        XCTAssertEqual(NativeSafeWebLink.resolve(url: "javascript:alert(1)", title: nil).label, "javascript:alert(1)")
        XCTAssertNil(NativeSafeWebLink.resolve(url: "not a URL", title: "").destination)
        XCTAssertEqual(NativeSafeWebLink.resolve(url: "not a URL", title: "").label, "not a URL")
    }

    func testUnknownOrMalformedWebViewFailsClosed() {
        let unknown = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("web"), "kind": .string("browse"), "truncated": .bool(false),
        ]))
        let malformedSearch = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("web"), "kind": .string("search"), "truncated": .bool(false),
            "sources": .array([.object(["url": .string("https://example.com"), "snippet": .number(1)])]),
        ]))
        let malformedFetch = ToolEventViewDTO(for: "result", view: .object([
            "card": .string("web"), "kind": .string("fetch"), "truncated": .bool(false),
            "url": .string("https://example.com"), "statusCode": .string("200"),
        ]))
        XCTAssertNil(unknown.nativeWebView)
        XCTAssertNil(malformedSearch.nativeWebView)
        XCTAssertNil(malformedFetch.nativeWebView)
    }
}
