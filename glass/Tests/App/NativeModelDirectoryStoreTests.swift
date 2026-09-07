import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeModelDirectoryStoreTests: XCTestCase {
    func testRefreshPreservesHostProviderDirectoryOrder() async {
        let api = DirectoryAPI(
            providers: [
                .init(provider: "zeta", displayName: "Zeta", settingsNs: "zeta", settingsPath: [], active: false, declared: nil),
                .init(provider: "alpha", displayName: "Alpha", settingsNs: "alpha", settingsPath: [], active: true, declared: true),
            ],
            models: .init(
                groups: [
                    .init(id: "group-b", name: "Group B", models: [.init(id: "model-b", name: "Model B", description: nil)]),
                    .init(id: "group-a", name: "Group A", models: [.init(id: "model-a", name: "Model A", description: nil)]),
                ],
                failures: [.init(id: "provider-failure", name: "Provider", message: "Host-safe failure")]
            )
        )
        let store = NativeModelDirectoryStore()

        await store.refresh(using: api)

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.providers.map(\.provider), ["zeta", "alpha"])
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.failures.isEmpty)
    }

    func testFailureDoesNotLeaveStaleOrInventedDirectory() async {
        let healthy = DirectoryAPI(
            providers: [.init(provider: "provider", displayName: "Provider", settingsNs: "provider", settingsPath: [], active: true, declared: true)],
            models: .init(groups: [], failures: [])
        )
        let failing = DirectoryAPI(providers: [], models: .init(groups: [], failures: []), shouldFail: true)
        let store = NativeModelDirectoryStore()
        await store.refresh(using: healthy)

        await store.refresh(using: failing)

        XCTAssertEqual(store.phase, .failed)
        XCTAssertTrue(store.providers.isEmpty)
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.failures.isEmpty)
    }

    private final class DirectoryAPI: NativeLLMDirectoryAPI, @unchecked Sendable {
        let providerResponse: LLMProvidersResponse
        let modelResponse: LLMModelsResponse
        let shouldFail: Bool

        init(providers: [LLMProviderDTO], models: LLMModelsResponse, shouldFail: Bool = false) {
            providerResponse = .init(providers: providers)
            modelResponse = models
            self.shouldFail = shouldFail
        }

        func providers() async throws -> LLMProvidersResponse {
            if shouldFail { throw DSHTransportError.network("offline") }
            return providerResponse
        }

        func models() async throws -> LLMModelsResponse {
            if shouldFail { throw DSHTransportError.network("offline") }
            return modelResponse
        }

        func discoverModels(_ request: LLMDiscoverModelsRequest) async throws -> LLMDiscoverModelsResponse {
            if shouldFail { throw DSHTransportError.network("offline") }
            return .init(models: [])
        }
    }
}
