import Foundation
import XCTest

@testable import GlassCore
@testable import GlassSpec

final class AuthenticatedHostFixtureTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

    func testControllerCatalogsDecodeWithProductionModels() throws {
        let fixture = try OfficialAuthenticatedHostFixtureCatalog.load()

        let commands = try RemoteWireCodec.response(
            [RemoteCommandDescriptor].self,
            data: encoderData(fixture.controllerCatalogs.commands.response),
            decoder: decoder
        )
        XCTAssertEqual(commands.rpcID, "fixture-commands-list")
        guard case let .value(commandValues) = decoded.result else {
            return XCTFail("authenticated commands/list fixture must succeed")
        }
        XCTAssertEqual(commandValues.map(\.name), ["compact", "export", "feedback", "goal", "permission", "plan"])
        XCTAssertEqual(commandValues.first(where: { $0.name == "goal" })?.input?.images, true)
        XCTAssertEqual(commandValues.first(where: { $0.name == "feedback" })?.input?.hint, "<text>")

        let skills = try RemoteWireCodec.response(
            RemoteSkillCatalog.self,
            data: encoderData(fixture.controllerCatalogs.skills.response),
            decoder: decoder
        )
        XCTAssertEqual(skills.rpcID, "fixture-skills-list")
        guard case let .value(skillCatalog) = skills.result else {
            return XCTFail("authenticated skills/list fixture must succeed")
        }
        XCTAssertTrue(skillCatalog.skills.isEmpty)
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
