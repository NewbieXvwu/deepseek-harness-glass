import Foundation
import XCTest

@testable import GlassCore
@testable import GlassSpec

final class AuthenticatedHostFixtureTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testFixtureMetadataAndSecretPolicyAreRc1Only() throws {
        let fixture = try OfficialAuthenticatedHostFixtureCatalog.load()
        XCTAssertEqual(fixture.officialSourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(fixture.fixtureRevision, "official-a66e470-authenticated-host-r1")
        XCTAssertEqual(fixture.payload.dshVersion, "0.1.2-rc.1")
        XCTAssertFalse(fixture.secretPolicy.persistedLaunchToken)
        XCTAssertFalse(fixture.secretPolicy.persistedCookie)
        XCTAssertFalse(fixture.secretPolicy.persistedAuthorization)
        XCTAssertFalse(fixture.secretPolicy.persistedUserCredentials)
        XCTAssertFalse(fixture.secretPolicy.persistedRealWorkspacePath)
        XCTAssertEqual(fixture.authentication.bootstrapStatus, 303)
        XCTAssertEqual(fixture.authentication.redirectLocation, "/")
        XCTAssertTrue(fixture.authentication.cookieInstalled)
        XCTAssertEqual(fixture.authentication.authenticatedRootStatus, 200)
    }

    func testUnaryCaptureUsesProductionRemoteCodec() throws {
        let fixture = try OfficialAuthenticatedHostFixtureCatalog.load()
        struct Empty: Codable {}
        struct Arguments: Codable { let _request: Empty }
        let encoded = try RemoteWireCodec.request(
            rpcID: "fixture-session-list",
            endpoint: "session/list",
            arguments: Arguments(_request: Empty()),
            encoder: encoder
        )
        XCTAssertEqual(try canonical(encoded), try canonical(encoder.encode(fixture.unary.request)))

        let decoded = try RemoteWireCodec.response(
            RemoteSessionListValue.self,
            data: encoderData(fixture.unary.response),
            decoder: decoder
        )
        XCTAssertEqual(decoded.rpcID, "fixture-session-list")
        guard case let .value(value) = decoded.result else {
            return XCTFail("authenticated fixture session/list must succeed")
        }
        XCTAssertTrue(value.items.isEmpty)
    }

    func testBusinessErrorCaptureUsesClosedRemoteFailure() throws {
        let fixture = try OfficialAuthenticatedHostFixtureCatalog.load()
        let decoded = try RemoteWireCodec.response(
            RemoteSessionAcceptedValue.self,
            data: encoderData(fixture.businessError.response),
            decoder: decoder
        )
        XCTAssertEqual(decoded.rpcID, "fixture-business-error")
        guard case let .failure(error) = decoded.result else {
            return XCTFail("authenticated fixture cancel must retain a business failure")
        }
        XCTAssertEqual(error.code, "session/not-found")
        XCTAssertEqual(error.details["sessionId"], .string("fixture-missing-session"))
    }

    func testMuxOpeningAndWorkspaceDeltaDecodeWithProductionModels() throws {
        let fixture = try OfficialAuthenticatedHostFixtureCatalog.load()
        let ready = try decoder.decode(
            RemoteEventDownlinkFrame.self,
            from: encoderData(fixture.streamOpening.eventReady.value)
        )
        XCTAssertEqual(ready, .ready(.init(clientId: "<fixture-client-id>", host: .init(home: "<fixture-home>"))))

        let baseline = try decoder.decode(
            RemoteWorkspaceFollowFrame.self,
            from: encoderData(fixture.streamOpening.workspaceBaseline.value)
        )
        XCTAssertEqual(baseline, .baseline(.init(items: [], archivedSessionIds: [])))

        let deltas = try fixture.streamDelta.frames.map {
            try decoder.decode(RemoteWorkspaceFollowFrame.self, from: encoderData($0.value))
        }
        XCTAssertEqual(deltas.count, 2)
        guard case let .upsert(workspace) = deltas[0], case let .order(order) = deltas[1] else {
            return XCTFail("workspace/follow must capture upsert then order")
        }
        XCTAssertEqual(workspace.workspaceId, "<fixture-workspace-id>")
        XCTAssertEqual(workspace.path, "<fixture-workspace>")
        XCTAssertEqual(order, ["<fixture-workspace-id>"])
    }

    func testDownloadCapturePinsAuthenticatedZipRoute() throws {
        let fixture = try OfficialAuthenticatedHostFixtureCatalog.load()
        XCTAssertEqual(fixture.download.request.method, "GET")
        XCTAssertEqual(fixture.download.request.path, "/api/session.export?sessionId=fixture-session")
        XCTAssertEqual(fixture.download.head.status, 200)
        XCTAssertEqual(fixture.download.get.status, 200)
        XCTAssertEqual(fixture.download.head.contentType, "application/zip")
        XCTAssertEqual(fixture.download.get.contentType, "application/zip")
        XCTAssertEqual(fixture.download.get.zipMagicHex, "504b0304")
    }

    private func encoderData(_ value: RemoteJSONValue) throws -> Data { try encoder.encode(value) }

    private func canonical(_ data: Data) throws -> Data {
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }
}
