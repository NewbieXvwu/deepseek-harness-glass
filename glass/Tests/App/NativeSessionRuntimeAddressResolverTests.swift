import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeSessionRuntimeAddressResolverTests: XCTestCase {
    func testOrdinarySessionHasOrdinaryAddress() {
        XCTAssertEqual(
            NativeSessionRuntimeAddressResolver.resolve(sessionID: "root", subagentRoute: nil),
            .session(sessionID: "root")
        )
    }

    func testContinuableCatalogChildKeepsParentAndMode() {
        let route = NativeSessionStore.SubagentRoute(
            parentSessionID: "parent",
            childSessionID: "child",
            mode: .continuable,
            parentAvailable: true
        )
        XCTAssertEqual(
            NativeSessionRuntimeAddressResolver.resolve(sessionID: "child", subagentRoute: route),
            .subagent(parentSessionID: "parent", childSessionID: "child", mode: .continuable)
        )
    }

    func testOneShotCatalogChildStaysReadOnlyAddress() {
        let route = NativeSessionStore.SubagentRoute(
            parentSessionID: "parent",
            childSessionID: "child",
            mode: .oneShot,
            parentAvailable: false
        )
        XCTAssertEqual(
            NativeSessionRuntimeAddressResolver.resolve(sessionID: "child", subagentRoute: route),
            .subagent(parentSessionID: "parent", childSessionID: "child", mode: .oneShot)
        )
    }

    func testStaleChildRouteCannotRetargetAnotherSession() {
        let stale = NativeSessionStore.SubagentRoute(
            parentSessionID: "parent",
            childSessionID: "old-child",
            mode: .continuable,
            parentAvailable: true
        )
        XCTAssertEqual(
            NativeSessionRuntimeAddressResolver.resolve(sessionID: "new-session", subagentRoute: stale),
            .session(sessionID: "new-session")
        )
    }
}
