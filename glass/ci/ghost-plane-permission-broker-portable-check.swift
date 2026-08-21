import Foundation

@main
struct GhostPlanePermissionBrokerPortableCheck {
    static func main() throws {
        var broker = GhostPlanePermissionBroker()
        try equal(broker.decision(for: "dsh-review-loop", capability: .notifications), .needsNativePrompt, "initial prompt")
        try equal(
            broker.resolveFirstRequest(pluginID: "dsh-review-loop", capability: .notifications, resolution: .grant),
            .granted,
            "first native grant"
        )
        try equal(
            broker.resolveFirstRequest(pluginID: "dsh-review-loop", capability: .notifications, resolution: .deny),
            .granted,
            "grant cannot be preauthorization-overwritten"
        )
        try equal(broker.decision(for: "dsh-review-loop", capability: .clipboardRead), .needsNativePrompt, "per-capability prompt")
        try equal(
            broker.resolveFirstRequest(pluginID: "dsh-review-loop", capability: .clipboardRead, resolution: .deny),
            .denied,
            "first native deny"
        )
        try check(broker.revoke(pluginID: "dsh-review-loop", capability: .clipboardRead), "revoke existing decision")
        try equal(broker.decision(for: "dsh-review-loop", capability: .clipboardRead), .needsNativePrompt, "revoke requires first prompt again")
        try equal(broker.decision(for: "<plugin>", capability: .download), .invalidPlugin, "invalid plugin decision")
        try equal(
            broker.resolveFirstRequest(pluginID: "<plugin>", capability: .download, resolution: .grant),
            .invalidPlugin,
            "invalid plugin resolution"
        )
        try check(!broker.revoke(pluginID: "<plugin>", capability: .download), "invalid plugin revoke")
        print("ghost plane permission broker portable check passed")
    }

    private static func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else { throw CheckFailure("\(label): expected \(expected), got \(actual)") }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message) }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
