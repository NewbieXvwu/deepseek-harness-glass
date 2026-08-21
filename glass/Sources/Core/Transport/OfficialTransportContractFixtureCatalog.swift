import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

enum OfficialTransportContractFixtureCatalog {
    struct Fixture: Decodable {
        let schemaVersion: Int
        let officialSourceCommit: String
        let contractRevision: String
        let fixtureRevision: String
        let fixtureClass: String
        let secretPolicy: String
        let records: [Record]
        let sseFrames: [SSEFrame]
    }

    struct Record: Decodable {
        let contract: String
        let request: RPCClientRequest
        let response: RPCServerResponse
    }

    struct SSEFrame: Decodable {
        let contract: String
        let frame: RPCServerRequest
    }

    static func load() throws -> Fixture {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = .main
        #endif
        guard let url = bundle.url(forResource: "official-transport-contract-fixtures", withExtension: "json") else {
            throw DSHTransportError.decoding("T4.6 transport contract fixture resource is missing")
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 1,
              fixture.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.contractRevision == "official-528c682e-transport-contract-r1",
              fixture.fixtureRevision == "official-528c682e-transport-fixtures-r1"
        else {
            throw DSHTransportError.decoding("T4.6 transport contract fixture metadata does not match the locked official build")
        }
        return fixture
    }
}
