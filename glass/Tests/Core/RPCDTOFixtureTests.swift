import Foundation
import XCTest

@testable import GlassCore
@testable import GlassSpec

final class RPCDTOFixtureTests: XCTestCase {
    func testPinnedFixtureMatchesOfficialBuildAndCoversEveryRecordedMethod() throws {
        let fixture = try OfficialRPCFixtureCatalog.load()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.officialSourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(fixture.fixtureRevision, "official-99f6f02-web-ui-r1")
        XCTAssertEqual(fixture.endpointClass, "isolated local pinned dsh web")
        XCTAssertEqual(fixture.records.count, 16)
        XCTAssertEqual(Set(fixture.records.map(\.method)).count, fixture.records.count)
        XCTAssertEqual(
            Set(fixture.records.map(\.method)),
            [
                "host.describe", "session.list", "session.history", "session.prompt", "session.cancel", "session.create", "session.search", "session.rename", "session.fork",
                "workspace.list", "workspace.create", "workspace.rename", "workspace.delete", "workspace.archiveSession",
                "settings.describe", "settings.mutate",
            ]
        )
    }

    func testEveryRecordedWireRequestAndResponseHasCanonicalCodableRoundTrip() throws {
        let fixture = try OfficialRPCFixtureCatalog.load()
        for record in fixture.records {
            XCTAssertEqual(record.curlExit, 0, "\(record.method) capture must complete against local pinned Host")
            XCTAssertEqual(record.request.type, "client-request", "\(record.method) request envelope")
            XCTAssertEqual(record.request.method, record.method, "\(record.method) request method")
            XCTAssertEqual(record.response.type, "server-response", "\(record.method) response envelope")
            XCTAssertEqual(record.response.rpcId, record.request.rpcId, "\(record.method) rpcId echo")

            let requestData = try JSONEncoder().encode(record.request)
            let roundTrippedRequest = try JSONDecoder().decode(RPCClientRequest.self, from: requestData)
            XCTAssertEqual(roundTrippedRequest, record.request, "\(record.method) request model")
            XCTAssertEqual(try canonicalJSON(requestData), try canonicalJSON(try JSONEncoder().encode(roundTrippedRequest)), "\(record.method) request wire")

            let responseData = try JSONEncoder().encode(record.response)
            let roundTrippedResponse = try JSONDecoder().decode(RPCServerResponse.self, from: responseData)
            XCTAssertEqual(roundTrippedResponse, record.response, "\(record.method) response model")
            XCTAssertEqual(try canonicalJSON(responseData), try canonicalJSON(try JSONEncoder().encode(roundTrippedResponse)), "\(record.method) response wire")
        }
    }

    func testEveryRecordedRequestPayloadDecodesIntoItsProductionDTOAndRoundTrips() throws {
        let fixture = try OfficialRPCFixtureCatalog.load()
        try assertRequestDTO(EmptyPayload.self, method: "host.describe", fixture: fixture)
        try assertRequestDTO(EmptyPayload.self, method: "workspace.list", fixture: fixture)
        try assertRequestDTO(EmptyPayload.self, method: "session.list", fixture: fixture)
        try assertRequestDTO(EmptyPayload.self, method: "settings.describe", fixture: fixture)
        try assertRequestDTO(WorkspaceCreateRequest.self, method: "workspace.create", fixture: fixture)
        try assertRequestDTO(SessionCreateRequest.self, method: "session.create", fixture: fixture)
        try assertRequestDTO(SessionHistoryRequest.self, method: "session.history", fixture: fixture)
        try assertRequestDTO(SessionPromptRequest.self, method: "session.prompt", fixture: fixture)
        try assertRequestDTO(SessionCancelRequest.self, method: "session.cancel", fixture: fixture)
        try assertRequestDTO(SessionSearchRequest.self, method: "session.search", fixture: fixture)
        try assertRequestDTO(SessionRenameRequest.self, method: "session.rename", fixture: fixture)
        try assertRequestDTO(SessionForkRequest.self, method: "session.fork", fixture: fixture)
        try assertRequestDTO(WorkspaceRenameRequest.self, method: "workspace.rename", fixture: fixture)
        try assertRequestDTO(WorkspaceDeleteRequest.self, method: "workspace.delete", fixture: fixture)
        try assertRequestDTO(WorkspaceArchiveSessionRequest.self, method: "workspace.archiveSession", fixture: fixture)
        try assertRequestDTO(SettingsMutateRequest.self, method: "settings.mutate", fixture: fixture)
    }

    func testEveryRecordedSuccessfulValueDecodesIntoItsProductionDTO() throws {
        let fixture = try OfficialRPCFixtureCatalog.load()
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, method: String) throws -> T {
            try decoder.decode(T.self, from: JSONEncoder().encode(try successValue(for: method, fixture: fixture)))
        }

        let hostDescribe = try decode(HostDescribeResponse.self, method: "host.describe")
        XCTAssertEqual(hostDescribe.canOpenPath, true)
        let workspaceList = try decode(WorkspaceListResponse.self, method: "workspace.list")
        XCTAssertEqual(workspaceList.items.count, 0)
        XCTAssertEqual(workspaceList.archivedSessionIds.count, 0)
        let sessionList = try decode(SessionListResponse.self, method: "session.list")
        XCTAssertEqual(sessionList.items.count, 0)
        let settingsDescribe = try decode(SettingsDescribeResponse.self, method: "settings.describe")
        XCTAssertTrue(settingsDescribe.writable)
        let workspaceCreate = try decode(WorkspaceCreateResponse.self, method: "workspace.create")
        XCTAssertTrue(workspaceCreate.created)
        XCTAssertFalse(workspaceCreate.workspace.workspaceId.isEmpty)
        let sessionCreate = try decode(SessionCreateResponse.self, method: "session.create")
        XCTAssertFalse(sessionCreate.sessionId.isEmpty)
    }

    func testRecordedBusinessFailuresDecodeIntoClosedRPCBusinessErrorDTO() throws {
        let fixture = try OfficialRPCFixtureCatalog.load()
        let expectedBusinessFailures: Set<String> = [
            "session.history", "session.prompt", "session.cancel", "session.search", "session.rename", "session.fork",
            "workspace.rename", "workspace.delete", "workspace.archiveSession", "settings.mutate",
        ]
        var observedFailures: Set<String> = []
        for record in fixture.records {
            guard case let .failure(error) = record.response.result else { continue }
            let decoded = try JSONDecoder().decode(RPCBusinessError.self, from: JSONEncoder().encode(error))
            XCTAssertEqual(decoded, error, "\(record.method) business error Codable model")
            XCTAssertFalse(error.code.isEmpty, "\(record.method) error code")
            XCTAssertFalse(error.message.isEmpty, "\(record.method) error message")
            observedFailures.insert(record.method)
        }
        XCTAssertEqual(observedFailures, expectedBusinessFailures)
    }

    private func assertRequestDTO<T: Codable>(
        _ type: T.Type,
        method: String,
        fixture: OfficialRPCFixtureCatalog.Fixture
    ) throws {
        guard let record = fixture.records.first(where: { $0.method == method }) else {
            throw FixtureLookupError.missingMethod(method)
        }
        let source = try JSONEncoder().encode(record.request.payload)
        let dto = try JSONDecoder().decode(T.self, from: source)
        let encoded = try JSONEncoder().encode(dto)
        XCTAssertEqual(try canonicalJSON(source), try canonicalJSON(encoded), "\(method) typed request DTO")
    }

    private func successValue(
        for method: String,
        fixture: OfficialRPCFixtureCatalog.Fixture
    ) throws -> JSONValue {
        guard let record = fixture.records.first(where: { $0.method == method }) else {
            throw FixtureLookupError.missingMethod(method)
        }
        guard case let .success(value) = record.response.result else {
            throw FixtureLookupError.expectedSuccess(method)
        }
        return value
    }

    private func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    private enum FixtureLookupError: Error {
        case missingMethod(String)
        case expectedSuccess(String)
    }
}
