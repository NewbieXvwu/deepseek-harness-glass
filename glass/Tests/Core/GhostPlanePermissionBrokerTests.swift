@testable import GlassCore
import XCTest

final class GhostPlanePermissionBrokerTests: XCTestCase {
    func testFirstRequestPromptsThenRememberedDecisionCannotBeOverwritten() {
        var broker = GhostPlanePermissionBroker()

        XCTAssertEqual(broker.decision(for: "dsh-review-loop", capability: .notifications), .needsNativePrompt)
        XCTAssertEqual(
            broker.resolveFirstRequest(
                pluginID: "dsh-review-loop",
                capability: .notifications,
                resolution: .grant
            ),
            .granted
        )
        XCTAssertEqual(
            broker.resolveFirstRequest(
                pluginID: "dsh-review-loop",
                capability: .notifications,
                resolution: .deny
            ),
            .granted
        )
        XCTAssertEqual(broker.records, [
            .init(pluginID: "dsh-review-loop", capability: .notifications, resolution: .grant),
        ])
    }

    func testDenyIsRememberedPerCapabilityAndRevokeReturnsToFirstPrompt() {
        var broker = GhostPlanePermissionBroker()
        _ = broker.resolveFirstRequest(
            pluginID: "dsh-review-loop",
            capability: .clipboardRead,
            resolution: .deny
        )

        XCTAssertEqual(broker.decision(for: "dsh-review-loop", capability: .clipboardRead), .denied)
        XCTAssertEqual(broker.decision(for: "dsh-review-loop", capability: .clipboardWrite), .needsNativePrompt)
        XCTAssertTrue(broker.revoke(pluginID: "dsh-review-loop", capability: .clipboardRead))
        XCTAssertEqual(broker.decision(for: "dsh-review-loop", capability: .clipboardRead), .needsNativePrompt)
        XCTAssertFalse(broker.revoke(pluginID: "dsh-review-loop", capability: .clipboardRead))
    }

    func testInvalidPluginIDCannotRequestResolveOrRevoke() {
        var broker = GhostPlanePermissionBroker()

        XCTAssertEqual(broker.decision(for: "<plugin>", capability: .download), .invalidPlugin)
        XCTAssertEqual(
            broker.resolveFirstRequest(pluginID: "<plugin>", capability: .download, resolution: .grant),
            .invalidPlugin
        )
        XCTAssertFalse(broker.revoke(pluginID: "<plugin>", capability: .download))
        XCTAssertTrue(broker.records.isEmpty)
    }
}
