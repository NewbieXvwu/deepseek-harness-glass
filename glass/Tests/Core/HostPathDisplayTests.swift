import XCTest

@testable import GlassCore

final class HostPathDisplayTests: XCTestCase {
    func testAbbreviatesPOSIXHomeAndDescendants() {
        XCTAssertEqual(HostPathDisplay.abbreviateHomePath("/Users/u", home: "/Users/u"), "~")
        XCTAssertEqual(HostPathDisplay.abbreviateHomePath("/Users/u/", home: "/Users/u/"), "~")
        XCTAssertEqual(
            HostPathDisplay.abbreviateHomePath("/Users/u/Documents/project", home: "/Users/u"),
            "~/Documents/project"
        )
    }

    func testRetainsNonHomeAndPrefixAdjacentPaths() {
        XCTAssertEqual(HostPathDisplay.abbreviateHomePath("/Users/u2/a.ts", home: "/Users/u"), "/Users/u2/a.ts")
        XCTAssertEqual(HostPathDisplay.abbreviateHomePath("src/a.ts", home: "/Users/u"), "src/a.ts")
        XCTAssertEqual(HostPathDisplay.abbreviateHomePath("/etc/hosts", home: "/"), "/etc/hosts")
        XCTAssertEqual(HostPathDisplay.abbreviateHomePath("/Users/u/a.ts", home: nil), "/Users/u/a.ts")
    }

    func testRetainsWindowsDriveAndUNCPaths() {
        XCTAssertEqual(
            HostPathDisplay.abbreviateHomePath("C:\\Users\\u\\project", home: "C:\\Users\\u"),
            "C:\\Users\\u\\project"
        )
        XCTAssertEqual(
            HostPathDisplay.abbreviateHomePath("\\\\server\\share\\u", home: "\\\\server\\share\\u"),
            "\\\\server\\share\\u"
        )
    }
}
