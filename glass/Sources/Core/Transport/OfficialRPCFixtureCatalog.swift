import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Versioned real Host captures used to prove the native wire DTOs against rc.7.
enum OfficialRPCFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        let schemaVersion: Int
        let officialSourceCommit: String
        let fixtureRevision: String
        let endpointClass: String
        let records: [Record]
    }

    struct Record: Decodable, Sendable {
        let method: String
        let request: RPCClientRequest
        let curlExit: Int
        let response: RPCServerResponse
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(forResource: "official-host-rpc-fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 1,
              fixture.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.fixtureRevision == "official-528c682e-web-ui-r1" else {
            throw FixtureError.incompatibleRevision
        }
        return fixture
    }

    private static var fixtureBundle: Bundle {
#if SWIFT_PACKAGE
        return .module
#else
        return .main
#endif
    }

    enum FixtureError: LocalizedError {
        case missingResource
        case incompatibleRevision

        var errorDescription: String? {
            switch self {
            case .missingResource: return "Official Host RPC fixture resource is missing."
            case .incompatibleRevision: return "Official Host RPC fixture does not match the generated UI specification."
            }
        }
    }
}
