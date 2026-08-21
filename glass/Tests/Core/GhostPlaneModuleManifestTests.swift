import Foundation
import XCTest
@testable import GlassCore

final class GhostPlaneModuleManifestTests: XCTestCase {
    private let policy = GhostPlaneLoopbackPolicy(
        origin: URL(string: "http://127.0.0.1:7342/")!,
        pluginIDs: ["dsh-a", "dsh-b"]
    )!

    func testAdmissionAcceptsExactOrderedClientGraphAndKnownStaticSeed() {
        let result = GhostPlaneModuleManifest.admit(
            data: validGraph.data(using: .utf8)!,
            policy: policy,
            staticModuleSpecifiers: ["@deepseek-ai/dsh-client-runtime/client"]
        )
        guard case let .admitted(manifest) = result else {
            return XCTFail("valid loopback module graph should admit: \(result)")
        }
        XCTAssertEqual(manifest.rev, "graph-r1")
        XCTAssertEqual(manifest.entries.map(\.id), ["dsh-a", "dsh-b"])
        XCTAssertEqual(manifest.entries[1].external, ["dsh-a/client", "@deepseek-ai/dsh-client-runtime/client"])
    }

    func testAdmissionRejectsURLMismatchUnregisteredGraphAndDependencyOrder() {
        assertRejected(
            #"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=other","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#,
            .invalidClientBundlePath
        )
        assertRejected(
            #"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-b/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#,
            .resourceIDMismatch
        )
        assertRejected(
            #"{"rev":"graph-r1","entries":[{"id":"dsh-b","url":"http://127.0.0.1:7342/plugins/dsh-b/client.js?rev=b-r1","rev":"b-r1","inject":[],"immediately":false,"external":["dsh-a"]},{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#,
            .dependencyAfterConsumer
        )
        assertRejected(
            #"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":["unknown"]}]}"#,
            .unknownExternalSpecifier
        )
    }

    func testAdmissionRejectsMalformedRevisionDuplicateIDsAndExternalResource() {
        assertRejected("{", .malformedWire)
        assertRejected(#"{"rev":"","entries":[]}"#, .emptyGraphRevision)
        assertRejected(
            #"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":[]},{"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r2","rev":"a-r2","inject":[],"immediately":false,"external":[]}]}"#,
            .duplicateEntryID
        )
        assertRejected(
            #"{"rev":"graph-r1","entries":[{"id":"dsh-a","url":"https://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":false,"external":[]}]}"#,
            .resourceDenied(.unsupportedScheme)
        )
    }

    private func assertRejected(_ wire: String, _ reason: GhostPlaneModuleManifest.Reason) {
        XCTAssertEqual(
            GhostPlaneModuleManifest.admit(
                data: wire.data(using: .utf8)!,
                policy: policy,
                staticModuleSpecifiers: []
            ),
            .rejected(reason),
            wire
        )
    }

    private let validGraph = #"""
    {"rev":"graph-r1","entries":[
      {"id":"dsh-a","url":"http://127.0.0.1:7342/plugins/dsh-a/client.js?rev=a-r1","rev":"a-r1","inject":[],"immediately":true,"external":[]},
      {"id":"dsh-b","url":"http://127.0.0.1:7342/plugins/dsh-b/client.js?rev=b-r1","rev":"b-r1","inject":["dsh-a"],"immediately":false,"external":["dsh-a/client","@deepseek-ai/dsh-client-runtime/client"]}
    ]}
    """#
}
