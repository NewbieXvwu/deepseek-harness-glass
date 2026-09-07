import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Secret-free records captured from the exact bundled rc.1 authenticated Host.
enum OfficialAuthenticatedHostFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        let schemaVersion: Int
        let officialSourceCommit: String
        let fixtureRevision: String
        let fixtureClass: String
        let payload: Payload
        let secretPolicy: SecretPolicy
        let authentication: Authentication
        let unary: RemoteRecord
        let streamOpening: StreamOpening
        let streamDelta: StreamDelta
        let businessError: RemoteRecord
        let download: Download
    }

    struct Payload: Decodable, Sendable {
        let dshVersion: String
        let packageLockSHA256: String
    }

    struct SecretPolicy: Decodable, Sendable {
        let persistedLaunchToken: Bool
        let persistedCookie: Bool
        let persistedAuthorization: Bool
        let persistedUserCredentials: Bool
        let persistedRealWorkspacePath: Bool
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
        guard fixture.schemaVersion == 1,
              fixture.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.fixtureRevision == "official-a66e470-authenticated-host-r1",
              fixture.payload.dshVersion == "0.1.2-rc.1"
        else {
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
