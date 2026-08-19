import XCTest

@testable import GlassCore
@testable import GlassSpec

final class TransportContractRegressionTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testFixtureMetadataAndRequiredContractSetArePinned() throws {
        let fixture = try OfficialTransportContractFixtureCatalog.load()
        XCTAssertEqual(fixture.officialSourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(fixture.contractRevision, "official-99f6f02-transport-contract-r1")
        XCTAssertEqual(fixture.fixtureRevision, "official-99f6f02-transport-fixtures-r1")
        XCTAssertFalse(fixture.secretPolicy.contains("real"))
        XCTAssertEqual(
            Set(fixture.records.map(\.contract)),
            ["session.history", "session.prompt", "session.cancel", "session.models", "settings.describe", "settings.mutate", "credentials.set", "llm.providers"]
        )
        XCTAssertEqual(Set(fixture.sseFrames.map(\.contract)), ["sse.mux", "sse.host"])
    }

    func testEveryRPCEnvelopeRoundTripsCanonicallyAndCorrelates() throws {
        let fixture = try OfficialTransportContractFixtureCatalog.load()
        for record in fixture.records {
            XCTAssertEqual(record.request.type, "client-request", record.contract)
            XCTAssertEqual(record.response.type, "server-response", record.contract)
            XCTAssertEqual(record.request.rpcId, record.response.rpcId, record.contract)
            XCTAssertEqual(try canonical(record.request), try canonical(try decoder.decode(RPCClientRequest.self, from: encoder.encode(record.request))), record.contract)
            XCTAssertEqual(try canonical(record.response), try canonical(try decoder.decode(RPCServerResponse.self, from: encoder.encode(record.response))), record.contract)
        }
    }

    func testEveryRequiredRequestUsesProductionDTOAndRoundTrips() throws {
        let fixture = try OfficialTransportContractFixtureCatalog.load()
        try assertRequest("session.history", SessionHistoryRequest.self, fixture)
        try assertRequest("session.prompt", SessionPromptRequest.self, fixture)
        try assertRequest("session.cancel", SessionCancelRequest.self, fixture)
        try assertRequest("session.models", SessionModelsRequest.self, fixture)
        try assertRequest("settings.describe", EmptyPayload.self, fixture)
        try assertRequest("settings.mutate", SettingsMutateRequest.self, fixture)
        try assertRequest("credentials.set", CredentialsSetRequest.self, fixture)
        try assertRequest("llm.providers", EmptyPayload.self, fixture)
    }

    func testSuccessValuesDecodeWithProductionDTOs() throws {
        let fixture = try OfficialTransportContractFixtureCatalog.load()
        let history: SessionHistoryResponse = try successValue("session.history", fixture)
        XCTAssertEqual(history.events.count, 0)
        XCTAssertEqual(history.projections?.asOfSeq, -1)

        let cancel: SessionCancelResponse = try successValue("session.cancel", fixture)
        XCTAssertTrue(cancel.accepted)

        let models: SessionModelsResponse = try successValue("session.models", fixture)
        XCTAssertEqual(models.current.provider, "deepseek-official")
        XCTAssertTrue(models.routable)
        XCTAssertEqual(models.groups.count, 0)

        let settings: SettingsDescribeResponse = try successValue("settings.describe", fixture)
        XCTAssertTrue(settings.writable)
        XCTAssertTrue(settings.hasDocument)

        let _: EmptyRPCResponse = try successValue("credentials.set", fixture)
        let providers: LLMProvidersResponse = try successValue("llm.providers", fixture)
        XCTAssertEqual(providers.providers.count, 0)
    }

    func testClosedBusinessErrorsIncludeRevisionConflict() throws {
        let fixture = try OfficialTransportContractFixtureCatalog.load()
        let prompt = try record("session.prompt", fixture).response
        let mutate = try record("settings.mutate", fixture).response
        guard case let .failure(promptError) = prompt.result,
              case let .failure(conflict) = mutate.result
        else {
            return XCTFail("T4.6 error fixtures must retain closed failure results")
        }
        XCTAssertEqual(promptError.code, "session-not-found")
        XCTAssertEqual(conflict.code, "settings-conflict")
        guard case let .object(details) = conflict.details else {
            return XCTFail("settings-conflict details must remain an object")
        }
        XCTAssertEqual(details["ns"]?.stringValue, "contract")
        XCTAssertEqual(details["expected"]?.numberValue, 4)
        XCTAssertEqual(details["actual"]?.numberValue, 5)
    }

    func testSSEEventProjectionAndHostFramesRetainOfficialServerRequestShape() throws {
        let fixture = try OfficialTransportContractFixtureCatalog.load()
        let event = try sse("contract-event-8", fixture)
        let projection = try sse("contract-projection-9", fixture)
        let host = try sse("contract-host-status", fixture)
        XCTAssertEqual(event.type, "server-request")
        XCTAssertEqual(event.method, "session/event")
        XCTAssertEqual(event.payload.objectValue?["event"]?.objectValue?["seq"]?.numberValue, 8)
        XCTAssertEqual(projection.method, "session/projection")
        XCTAssertEqual(projection.payload.objectValue?["seq"]?.numberValue, 9)
        XCTAssertEqual(host.method, "host/session-status")
        XCTAssertEqual(host.payload.objectValue?["running"]?.boolValue, false)
    }

    private func record(_ contract: String, _ fixture: OfficialTransportContractFixtureCatalog.Fixture) throws -> OfficialTransportContractFixtureCatalog.Record {
        guard let record = fixture.records.first(where: { $0.contract == contract }) else {
            throw DSHTransportError.decoding("T4.6 fixture missing \(contract)")
        }
        return record
    }

    private func sse(_ rpcID: String, _ fixture: OfficialTransportContractFixtureCatalog.Fixture) throws -> RPCServerRequest {
        guard let frame = fixture.sseFrames.first(where: { $0.frame.rpcId == rpcID }) else {
            throw DSHTransportError.decoding("T4.6 fixture missing SSE \(rpcID)")
        }
        return frame.frame
    }

    private func assertRequest<T: Codable>(_ contract: String, _ type: T.Type, _ fixture: OfficialTransportContractFixtureCatalog.Fixture) throws {
        let request = try record(contract, fixture).request
        let decoded = try decoder.decode(T.self, from: encoder.encode(request.payload))
        XCTAssertEqual(try canonical(decoded), try canonical(try decoder.decode(T.self, from: encoder.encode(decoded))), contract)
    }

    private func successValue<T: Decodable>(_ contract: String, _ fixture: OfficialTransportContractFixtureCatalog.Fixture) throws -> T {
        let response = try record(contract, fixture).response
        guard case let .success(value) = response.result else {
            throw DSHTransportError.decoding("T4.6 expected success response for \(contract)")
        }
        return try decoder.decode(T.self, from: encoder.encode(value))
    }

    private func canonical<T: Encodable>(_ value: T) throws -> String {
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
