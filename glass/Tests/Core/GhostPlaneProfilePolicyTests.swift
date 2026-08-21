@testable import GlassCore
import XCTest

final class GhostPlaneProfilePolicyTests: XCTestCase {
    func testSharedWebAllowsNonCompetingRuntimeButRejectsExclusiveStdioAndTUI() {
        let policy = GhostPlaneProfilePolicy(dshHome: URL(fileURLWithPath: "/tmp/dsh"))
        XCTAssertEqual(policy.decision(selection: .sharedWeb, runtime: .declarativeUI), .allow(profilePath: "/tmp/dsh/profiles/web"))
        XCTAssertEqual(policy.decision(selection: .sharedWeb, runtime: .sharedService), .allow(profilePath: "/tmp/dsh/profiles/web"))
        XCTAssertEqual(policy.decision(selection: .sharedWeb, runtime: .exclusiveStdio), .requiresIsolatedProfile(runtime: .exclusiveStdio))
        XCTAssertEqual(policy.decision(selection: .sharedWeb, runtime: .tui), .requiresIsolatedProfile(runtime: .tui))
    }

    func testExplicitIsolatedProfileIsValidatedAndAllowsCompetingRuntime() {
        let policy = GhostPlaneProfilePolicy(dshHome: URL(fileURLWithPath: "/tmp/dsh"))
        XCTAssertEqual(policy.decision(selection: .isolated(name: "review-1"), runtime: .tui), .allow(profilePath: "/tmp/dsh/profiles/glass-review-1"))
        XCTAssertEqual(policy.decision(selection: .isolated(name: "../escape"), runtime: .exclusiveStdio), .invalidIsolatedName)
    }
}
