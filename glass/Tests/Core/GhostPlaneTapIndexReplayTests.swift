@testable import GlassCore
import XCTest

final class GhostPlaneTapIndexReplayTests: XCTestCase {
    func testAdmitsSourceBoundTokenDataAndClassMutationsInHostOrder() throws {
        let manifest = try admittedManifest()
        let source = GhostPlaneTapIndexReplay.Source(pluginID: "dsh-review-loop", revision: "r1")
        let records: [GhostPlaneTapIndexReplay.Record] = [
            .init(
                source: source,
                target: .planeRoot,
                mutation: .setCustomProperty(name: "--dsh-accent", value: "#3b82f6")
            ),
            .init(
                source: source,
                target: .detailsTool,
                mutation: .setDataAttribute(name: "data-ghost-mode", value: "review")
            ),
            .init(
                source: source,
                target: .turnTail,
                mutation: .addCompatibilityClass("ghost-compat-review-tail")
            ),
        ]

        let replay = try XCTUnwrap(admitted(records, manifest: manifest))

        XCTAssertEqual(replay.graphRevision, "graph-r1")
        XCTAssertEqual(replay.records, records)
        XCTAssertEqual(replay.rendererPayload(), [
            [
                "pluginID": "dsh-review-loop",
                "revision": "r1",
                "targetID": "ghost-plane-root",
                "kind": "customProperty",
                "name": "--dsh-accent",
                "value": "#3b82f6",
            ],
            [
                "pluginID": "dsh-review-loop",
                "revision": "r1",
                "targetID": "ghost-details-tool",
                "kind": "dataAttribute",
                "name": "data-ghost-mode",
                "value": "review",
            ],
            [
                "pluginID": "dsh-review-loop",
                "revision": "r1",
                "targetID": "ghost-turn-tail",
                "kind": "compatibilityClass",
                "name": "ghost-compat-review-tail",
            ],
        ])
    }

    func testRejectsUnknownOrStaleSourceAndConflictingWrite() throws {
        let manifest = try admittedManifest()
        let mutation = GhostPlaneTapIndexReplay.Mutation.setCustomProperty(name: "--dsh-accent", value: "blue")

        XCTAssertEqual(
            GhostPlaneTapIndexReplay.admit(
                records: [.init(
                    source: .init(pluginID: "other", revision: "r1"),
                    target: .planeRoot,
                    mutation: mutation
                )],
                for: manifest
            ),
            .rejected(.unknownPlugin)
        )
        XCTAssertEqual(
            GhostPlaneTapIndexReplay.admit(
                records: [.init(
                    source: .init(pluginID: "dsh-review-loop", revision: "stale"),
                    target: .planeRoot,
                    mutation: mutation
                )],
                for: manifest
            ),
            .rejected(.revisionMismatch)
        )
        XCTAssertEqual(
            GhostPlaneTapIndexReplay.admit(
                records: [
                    .init(
                        source: .init(pluginID: "dsh-review-loop", revision: "r1"),
                        target: .planeRoot,
                        mutation: mutation
                    ),
                    .init(
                        source: .init(pluginID: "dsh-review-loop", revision: "r1"),
                        target: .planeRoot,
                        mutation: mutation
                    ),
                ],
                for: manifest
            ),
            .rejected(.duplicateMutation)
        )
    }

    func testRejectsExecutableOrUnscopedMutationSurface() throws {
        let manifest = try admittedManifest()
        let source = GhostPlaneTapIndexReplay.Source(pluginID: "dsh-review-loop", revision: "r1")
        let examples: [(GhostPlaneTapIndexReplay.Mutation, GhostPlaneTapIndexReplay.Rejection)] = [
            (.setCustomProperty(name: "color", value: "blue"), .unsafeCustomPropertyName),
            (.setCustomProperty(name: "--dsh-bg", value: "url(https://evil.example/a)"), .unsafeCustomPropertyValue),
            (.setDataAttribute(name: "onclick", value: "run"), .unsafeDataAttributeName),
            (.setDataAttribute(name: "data-ghost-mode", value: "<script>"), .unsafeDataAttributeValue),
            (.addCompatibilityClass("plugin-class"), .unsafeCompatibilityClass),
        ]

        for (mutation, expected) in examples {
            XCTAssertEqual(
                GhostPlaneTapIndexReplay.admit(
                    records: [.init(source: source, target: .planeRoot, mutation: mutation)],
                    for: manifest
                ),
                .rejected(expected)
            )
        }
    }

    private func admittedManifest() throws -> GhostPlaneModuleManifest {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-review-loop"]
        ))
        let data = Data("""
        {"rev":"graph-r1","entries":[{"id":"dsh-review-loop","url":"http://127.0.0.1:7342/plugins/??dsh-review-loop/client.js&rev=r1","rev":"r1","inject":[],"immediately":true,"external":[]}],"batches":[{"phase":"application","url":"http://127.0.0.1:7342/plugins/??dsh-review-loop/client.js&rev=batch-r1","rev":"batch-r1","entries":["dsh-review-loop"]}]}
        """.utf8)
        guard case .admitted(let manifest) = GhostPlaneModuleManifest.admit(
            data: data,
            policy: policy,
            staticModuleSpecifiers: []
        ) else {
            return try XCTUnwrap(nil)
        }
        return manifest
    }

    private func admitted(
        _ records: [GhostPlaneTapIndexReplay.Record],
        manifest: GhostPlaneModuleManifest
    ) -> GhostPlaneTapIndexReplay? {
        guard case .admitted(let replay) = GhostPlaneTapIndexReplay.admit(records: records, for: manifest) else {
            return nil
        }
        return replay
    }
}
