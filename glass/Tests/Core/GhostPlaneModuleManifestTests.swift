import Foundation
import XCTest
@testable import GlassCore

final class GhostPlaneModuleManifestTests: XCTestCase {
    private let policy = GhostPlaneLoopbackPolicy(
        origin: URL(string: "http://127.0.0.1:7342/")!,
        pluginIDs: ["@deepseek-ai/dsh-client-modules", "@deepseek-ai/dsh-ui-chat"]
    )!

    func testAdmissionAcceptsRc1EntriesAndInitialLoadBatches() {
        let result = GhostPlaneModuleManifest.admit(data: validGraph.data(using: .utf8)!, policy: policy, staticModuleSpecifiers: ["react"])
        guard case let .admitted(manifest) = result else { return XCTFail("expected rc1 graph admission: \(result)") }
        XCTAssertEqual(manifest.entries.map(\.id), ["@deepseek-ai/dsh-client-modules", "@deepseek-ai/dsh-ui-chat"])
        XCTAssertEqual(manifest.batches.map(\.phase), [.bootstrap, .application])
    }

    func testAdmissionRejectsMissingOrDuplicateBatchMembership() {
        let missing = #"""
        {"rev":"graph-r1","entries":[
          {"id":"@deepseek-ai/dsh-client-modules","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=modules-r1","rev":"modules-r1","inject":[],"immediately":true,"external":[]},
          {"id":"@deepseek-ai/dsh-ui-chat","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=chat-r1","rev":"chat-r1","inject":["@deepseek-ai/dsh-client-modules"],"immediately":false,"external":["react"]}
        ],"batches":[
          {"phase":"bootstrap","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=boot-r1","rev":"boot-r1","entries":["@deepseek-ai/dsh-client-modules"]}
        ]}
        """#
        assertRejected(missing, .missingBatchMembership)

        let duplicate = #"""
        {"rev":"graph-r1","entries":[
          {"id":"@deepseek-ai/dsh-client-modules","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=modules-r1","rev":"modules-r1","inject":[],"immediately":true,"external":[]},
          {"id":"@deepseek-ai/dsh-ui-chat","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=chat-r1","rev":"chat-r1","inject":["@deepseek-ai/dsh-client-modules"],"immediately":false,"external":["react"]}
        ],"batches":[
          {"phase":"bootstrap","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=boot-r1","rev":"boot-r1","entries":["@deepseek-ai/dsh-client-modules", "@deepseek-ai/dsh-client-modules"]}
        ]}
        """#
        assertRejected(duplicate, .duplicateBatchMembership)
    }

    func testAdmissionRejectsWrongSingleResourceComboAndDependencyOrder() {
        let wrong = validGraph.replacingOccurrences(of: "@deepseek-ai/dsh-ui-chat/client.js&rev=chat-r1", with: "@deepseek-ai/dsh-client-modules/client.js&rev=chat-r1")
        assertRejected(wrong, .resourceIDMismatch)
        let order = validGraph.replacingOccurrences(of: #""external":[]"#, with: #""external":["@deepseek-ai/dsh-ui-chat"]"#)
        assertRejected(order, .dependencyAfterConsumer)
    }

    private func assertRejected(_ wire: String, _ reason: GhostPlaneModuleManifest.Reason) {
        XCTAssertEqual(GhostPlaneModuleManifest.admit(data: wire.data(using: .utf8)!, policy: policy, staticModuleSpecifiers: ["react"]), .rejected(reason))
    }

    private let validGraph = #"""
    {"rev":"graph-r1","entries":[
      {"id":"@deepseek-ai/dsh-client-modules","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=modules-r1","rev":"modules-r1","inject":[],"immediately":true,"external":[]},
      {"id":"@deepseek-ai/dsh-ui-chat","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=chat-r1","rev":"chat-r1","inject":["@deepseek-ai/dsh-client-modules"],"immediately":false,"external":["react"]}
    ],"batches":[
      {"phase":"bootstrap","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=boot-r1","rev":"boot-r1","entries":["@deepseek-ai/dsh-client-modules"]},
      {"phase":"application","url":"http://127.0.0.1:7342/plugins/??@deepseek-ai/dsh-ui-chat/client.js&rev=app-r1","rev":"app-r1","entries":["@deepseek-ai/dsh-ui-chat"]}
    ]}
    """#
}
