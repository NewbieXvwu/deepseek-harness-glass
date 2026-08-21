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

    func testLateDiscoveryResponseCannotOverwriteNewerHostCandidates() async {
        let oldReached = expectation(description: "older discovery waits at Host boundary")
        let api = DelayedDiscoveryAPI(oldReached: oldReached)
        let store = NativeModelDiscoveryStore()
        let oldTask = Task { await store.discover(request(provider: "slow"), using: api) }
        await fulfillment(of: [oldReached], timeout: 1)

        await store.discover(request(provider: "fresh"), using: api)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.candidates.map(\.id), ["fresh-model"])

        await api.releaseOldResponse()
        await oldTask.value
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.candidates.map(\.id), ["fresh-model"])
    }

    func testDismissSuppressesLateDiscoveryCandidates() async {
        let oldReached = expectation(description: "discovery reaches Host before dismiss")
        let api = DelayedDiscoveryAPI(oldReached: oldReached)
        let store = NativeModelDiscoveryStore()
        let task = Task { await store.discover(request(provider: "slow"), using: api) }
        await fulfillment(of: [oldReached], timeout: 1)

        store.dismiss()
        await api.releaseOldResponse()
        await task.value

        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(store.candidates.isEmpty)
    }

    private func request(provider: String = "provider") -> LLMDiscoverModelsRequest {
        .init(settingsNs: "provider-settings", provider: provider, baseURL: "https://models.test", api: nil, apiKey: "ephemeral-test-key")
    }

    private final class DelayedDiscoveryAPI: NativeLLMDirectoryAPI, @unchecked Sendable {
        let oldReached: XCTestExpectation
        private let gate = RecoveryGate()

        init(oldReached: XCTestExpectation) {
            self.oldReached = oldReached
        }

        func releaseOldResponse() async {
            await gate.open()
        }

        func providers() async throws -> LLMProvidersResponse { .init(providers: []) }
        func models() async throws -> LLMModelsResponse { .init(groups: [], failures: []) }
        func discoverModels(_ request: LLMDiscoverModelsRequest) async throws -> LLMDiscoverModelsResponse {
            if request.provider == "slow" {
                oldReached.fulfill()
                await gate.wait()
                return .init(models: [.init(id: "slow-model", name: "Slow Model", contextWindow: 8_192, maxTokens: 1_024)])
            }
            return .init(models: [.init(id: "fresh-model", name: "Fresh Model", contextWindow: 128_000, maxTokens: 8_192)])
        }
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
