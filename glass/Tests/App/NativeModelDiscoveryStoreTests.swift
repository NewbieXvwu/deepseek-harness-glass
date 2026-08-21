import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeModelDiscoveryStoreTests: XCTestCase {
    func testDiscoveryPublishesOnlyHostReturnedCandidates() async {
        let api = DiscoveryAPI(result: .init(models: [
            .init(id: "host-model", name: "Host Model", contextWindow: 128_000, maxTokens: 8_192),
        ]))
        let store = NativeModelDiscoveryStore()

        await store.discover(request(), using: api)

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.candidates.map(\.id), ["host-model"])
        XCTAssertEqual(api.requests.map(\.settingsNs), ["provider-settings"])
    }

    func testEmptyAndFailedDiscoveryDoNotRetainCandidates() async {
        let empty = DiscoveryAPI(result: .init(models: []))
        let failed = DiscoveryAPI(result: .init(models: []), shouldFail: true)
        let store = NativeModelDiscoveryStore()

        await store.discover(request(), using: empty)
        XCTAssertEqual(store.phase, .empty)
        XCTAssertTrue(store.candidates.isEmpty)

        await store.discover(request(), using: failed)
        XCTAssertEqual(store.phase, .failed)
        XCTAssertTrue(store.candidates.isEmpty)
        store.dismiss()
        XCTAssertEqual(store.phase, .idle)
    }

    private func request() -> LLMDiscoverModelsRequest {
        .init(settingsNs: "provider-settings", provider: "provider", baseURL: "https://models.test", api: nil, apiKey: "ephemeral-test-key")
    }

    private final class DiscoveryAPI: NativeLLMDirectoryAPI, @unchecked Sendable {
        let result: LLMDiscoverModelsResponse
        let shouldFail: Bool
        private(set) var requests: [LLMDiscoverModelsRequest] = []

        init(result: LLMDiscoverModelsResponse, shouldFail: Bool = false) {
            self.result = result
            self.shouldFail = shouldFail
        }

        func providers() async throws -> LLMProvidersResponse { .init(providers: []) }
        func models() async throws -> LLMModelsResponse { .init(groups: [], failures: []) }
        func discoverModels(_ request: LLMDiscoverModelsRequest) async throws -> LLMDiscoverModelsResponse {
            if shouldFail { throw DSHTransportError.network("offline") }
            requests.append(request)
            return result
        }
    }
}
