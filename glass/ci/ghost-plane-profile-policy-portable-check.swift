import Foundation

@main
struct GhostPlaneProfilePolicyPortableCheck {
    static func main() throws {
        let policy = GhostPlaneProfilePolicy(dshHome: URL(fileURLWithPath: "/tmp/dsh"))
        try equal(policy.decision(selection: .sharedWeb, runtime: .declarativeUI), .allow(profilePath: "/tmp/dsh/profiles/web"), "shared declarative")
        try equal(policy.decision(selection: .sharedWeb, runtime: .exclusiveStdio), .requiresIsolatedProfile(runtime: .exclusiveStdio), "shared stdio")
        try equal(policy.decision(selection: .sharedWeb, runtime: .tui), .requiresIsolatedProfile(runtime: .tui), "shared tui")
        try equal(policy.decision(selection: .isolated(name: "review-1"), runtime: .tui), .allow(profilePath: "/tmp/dsh/profiles/glass-review-1"), "isolated tui")
        try equal(policy.decision(selection: .isolated(name: "../escape"), runtime: .tui), .invalidIsolatedName, "unsafe profile name")
        print("ghost plane profile policy portable check passed")
    }
    private static func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else { throw Failure("\(label): expected \(expected), got \(actual)") }
    }
}
private struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
