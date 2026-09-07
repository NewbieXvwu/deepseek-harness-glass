import GlassPluginPlane
import XCTest

@MainActor
final class GhostPlaneExternalNavigationAdapterTests: XCTestCase {
    func testCredentialFreeHTTPSTargetRequiresExactNativeConfirmation() {
        let expected = URL(string: "https://example.com/docs?q=rc1")!
        var confirmed: [URL] = []
        var opened: [URL] = []
        let adapter = GhostPlaneExternalNavigationAdapter(
            confirmation: { url in confirmed.append(url); return true },
            opener: { url in opened.append(url); return true }
        )

        XCTAssertTrue(adapter.open(expected))
        XCTAssertEqual(confirmed, [expected])
        XCTAssertEqual(opened, [expected])
    }

    func testRejectsUnsafeSchemesCredentialsAndNativeCancellation() {
        var opened: [URL] = []
        let adapter = GhostPlaneExternalNavigationAdapter(
            confirmation: { _ in false },
            opener: { url in opened.append(url); return true }
        )

        XCTAssertFalse(adapter.open(URL(string: "https://example.com/cancel")!))
        XCTAssertFalse(adapter.open(URL(string: "https://user:secret@example.com/")!))
        XCTAssertFalse(adapter.open(URL(string: "file:///tmp/private")!))
        XCTAssertFalse(adapter.open(URL(string: "javascript:alert(1)")!))
        XCTAssertTrue(opened.isEmpty)
    }
}
