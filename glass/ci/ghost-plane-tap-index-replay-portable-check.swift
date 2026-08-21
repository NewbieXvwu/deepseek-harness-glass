import Foundation

@main
struct GhostPlaneTapIndexReplayPortableCheck {
    static func main() throws {
        let policy = try expect(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-review-loop"]
        ))
        let data = Data("""
        {"rev":"graph-r1","entries":[{"id":"dsh-review-loop","url":"http://127.0.0.1:7342/plugins/dsh-review-loop/client.js?rev=r1","rev":"r1","inject":[],"immediately":true,"external":[]}]}
        """.utf8)
        let manifest: GhostPlaneModuleManifest
        switch GhostPlaneModuleManifest.admit(data: data, policy: policy, staticModuleSpecifiers: []) {
        case .admitted(let value): manifest = value
        case .rejected(let reason): throw CheckFailure("fixture rejected: \(reason)")
        }

        let source = GhostPlaneTapIndexReplay.Source(pluginID: "dsh-review-loop", revision: "r1")
        let records: [GhostPlaneTapIndexReplay.Record] = [
            .init(
                source: source,
                target: .planeRoot,
                mutation: .setCustomProperty(name: "--dsh-accent", value: "#3b82f6")
            ),
            .init(
                source: source,
                target: .toolview,
                mutation: .setDataAttribute(name: "data-ghost-mode", value: "review")
            ),
            .init(
                source: source,
                target: .turnTail,
                mutation: .addCompatibilityClass("ghost-compat-review-tail")
            ),
        ]
        let replay: GhostPlaneTapIndexReplay
        switch GhostPlaneTapIndexReplay.admit(records: records, for: manifest) {
        case .admitted(let value): replay = value
        case .rejected(let reason): throw CheckFailure("valid replay rejected: \(reason)")
        }
        try check(replay.graphRevision == "graph-r1", "graph revision was not retained")
        try check(replay.records == records, "host order was not retained")
        try check(
            replay.rendererPayload().first == [
                "pluginID": "dsh-review-loop",
                "revision": "r1",
                "targetID": "ghost-plane-root",
                "kind": "customProperty",
                "name": "--dsh-accent",
                "value": "#3b82f6",
            ],
            "payload does not use primitive parameterized data"
        )

        try reject(
            [.init(
                source: .init(pluginID: "unknown", revision: "r1"),
                target: .planeRoot,
                mutation: .setDataAttribute(name: "data-ghost-mode", value: "review")
            )],
            manifest: manifest,
            equals: .unknownPlugin
        )
        try reject(
            [.init(
                source: .init(pluginID: "dsh-review-loop", revision: "stale"),
                target: .planeRoot,
                mutation: .setDataAttribute(name: "data-ghost-mode", value: "review")
            )],
            manifest: manifest,
            equals: .revisionMismatch
        )
        let duplicate = GhostPlaneTapIndexReplay.Mutation.setCustomProperty(name: "--dsh-accent", value: "blue")
        try reject(
            [
                .init(source: source, target: .planeRoot, mutation: duplicate),
                .init(source: source, target: .planeRoot, mutation: duplicate),
            ],
            manifest: manifest,
            equals: .duplicateMutation
        )
        try reject(
            [.init(
                source: source,
                target: .planeRoot,
                mutation: .setCustomProperty(name: "--dsh-bg", value: "url(https://evil.example/a)")
            )],
            manifest: manifest,
            equals: .unsafeCustomPropertyValue
        )
        try reject(
            [.init(
                source: source,
                target: .planeRoot,
                mutation: .setDataAttribute(name: "onclick", value: "run")
            )],
            manifest: manifest,
            equals: .unsafeDataAttributeName
        )
        try reject(
            [.init(
                source: source,
                target: .planeRoot,
                mutation: .addCompatibilityClass("plugin-class")
            )],
            manifest: manifest,
            equals: .unsafeCompatibilityClass
        )

        print("ghost plane tap index replay portable check passed")
    }

    private static func reject(
        _ records: [GhostPlaneTapIndexReplay.Record],
        manifest: GhostPlaneModuleManifest,
        equals expected: GhostPlaneTapIndexReplay.Rejection
    ) throws {
        guard case .rejected(let actual) = GhostPlaneTapIndexReplay.admit(records: records, for: manifest) else {
            throw CheckFailure("expected rejection \(expected), got admission")
        }
        try check(actual == expected, "expected rejection \(expected), got \(actual)")
    }

    private static func expect<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure("required fixture was nil") }
        return value
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
