import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeModelDirectoryStoreTests: XCTestCase {
    func testRefreshPreservesHostProviderDirectoryOrder() async {
        let api = DirectoryAPI(providers: [
            .init(provider: "zeta", displayName: "Zeta", settingsNs: "zeta", settingsPath: [], active: false, declared: nil),
            .init(provider: "alpha", displayName: "Alpha", settingsNs: "alpha", settingsPath: [], active: true, declared: true),
        ])
        let store = NativeModelDirectoryStore()

        await store.refresh(using: api)

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.providers.map(\.provider), ["zeta", "alpha"])
    }

    func testFailureDoesNotLeaveStaleOrInventedDirectory() async {
        let healthy = DirectoryAPI(providers: [
            .init(provider: "provider", displayName: "Provider", settingsNs: "provider", settingsPath: [], active: true, declared: true),
        ])
        let failing = DirectoryAPI(providers: [], shouldFail: true)
        let store = NativeModelDirectoryStore()
        await store.refresh(using: healthy)

        await store.refresh(using: failing)

        XCTAssertEqual(store.phase, .failed)
        XCTAssertTrue(store.providers.isEmpty)
    }

    private final class DirectoryAPI: NativeLLMDirectoryAPI, @unchecked Sendable {
        let providerResponse: LLMProvidersResponse
        let shouldFail: Bool

        init(providers: [LLMProviderDTO], shouldFail: Bool = false) {
            providerResponse = .init(providers: providers)
            self.shouldFail = shouldFail
        }

        func providers() async throws -> LLMProvidersResponse {
            if shouldFail { throw DSHTransportError.network("offline") }
            return providerResponse
        }

        func discoverModels(_ request: LLMDiscoverModelsRequest) async throws -> LLMDiscoverModelsResponse {
            if shouldFail { throw DSHTransportError.network("offline") }
            return .init(models: [])
        }
    }
}
