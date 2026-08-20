import XCTest

@testable import GlassUI

@MainActor
final class NativeWorkspaceStoreTests: XCTestCase {
    func testSearchSanitizerMatchesRC8NULAndUTF16BoundaryContract() {
        XCTAssertEqual(
            NativeWorkspaceStore.sanitizeSearchQuery("before\u{0000}after"),
            "beforeafter"
        )

        let withinBoundary = String(repeating: "a", count: 500)
        XCTAssertEqual(NativeWorkspaceStore.sanitizeSearchQuery(withinBoundary), withinBoundary)

        // 499 BMP code units followed by a two-code-unit scalar crosses the
        // 500-unit wire edge. RC8 backs up one unit so a dangling high
        // surrogate never reaches the Host search request.
        let pairAtBoundary = String(repeating: "a", count: 499) + "😀" + "z"
        let sanitizedBoundary = NativeWorkspaceStore.sanitizeSearchQuery(pairAtBoundary)
        XCTAssertEqual(sanitizedBoundary, String(repeating: "a", count: 499))
        XCTAssertEqual(sanitizedBoundary.utf16.count, 499)

        let ordinaryOverflow = String(repeating: "b", count: 501)
        let sanitizedOverflow = NativeWorkspaceStore.sanitizeSearchQuery(ordinaryOverflow)
        XCTAssertEqual(sanitizedOverflow, String(repeating: "b", count: 500))
        XCTAssertEqual(sanitizedOverflow.utf16.count, 500)
    }
}
