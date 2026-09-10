import Foundation

/// Secret-free records captured from an authenticated local Host.
enum OfficialAuthenticatedHostFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        let schemaVersion: Int
        let authentication: Authentication
        let unary: RemoteRecord
        let streamOpening: StreamOpening
        let streamDelta: StreamDelta
        let controllerCatalogs: ControllerCatalogs
        let businessError: RemoteRecord
        let download: Download
    }

    struct Authentication: Decodable, Sendable {
        let bootstrapStatus: Int
        let redirectLocation: String
        let cookieInstalled: Bool
        let authenticatedRootStatus: Int
    }

    struct RemoteRecord: Decodable, Sendable {
        let endpoint: String
        let request: RemoteJSONValue
        let httpStatus: Int
        let contentType: String
        let response: RemoteJSONValue
    }

    struct StreamOpening: Decodable, Sendable {
        let eventRequest: RemoteJSONValue
        let eventReady: MuxFrame
        let workspaceRequest: RemoteJSONValue
        let workspaceBaseline: MuxFrame
    }

    struct StreamDelta: Decodable, Sendable {
        let trigger: RemoteJSONValue
        let frames: [MuxFrame]
    }

    struct ControllerCatalogs: Decodable, Sendable {
        let commands: RemoteRecord
        let skills: RemoteRecord
    }

    struct MuxFrame: Decodable, Sendable {
        let type: String
        let streamId: String
        let value: RemoteJSONValue
    }

    struct Download: Decodable, Sendable {
        let request: DownloadRequest
        let head: DownloadFacts
        let get: DownloadFacts
    }

    struct DownloadRequest: Decodable, Sendable {
        let method: String
        let path: String
    }

    struct DownloadFacts: Decodable, Sendable {
        let status: Int
        let contentType: String
        let contentDisposition: String
        let zipMagicHex: String?
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(
            forResource: "official-authenticated-host-fixtures",
            withExtension: "json"
        ) else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 1 else {
            throw FixtureError.incompatibleRevision
        }
        return fixture
    }

    private static var fixtureBundle: Bundle {
#if SWIFT_PACKAGE
        .module
#else
        .main
#endif
    }

    enum FixtureError: Error {
        case missingResource
        case incompatibleRevision
    }
}
