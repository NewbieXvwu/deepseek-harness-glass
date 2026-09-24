import XCTest
@testable import GlassCore

final class ModelCatalogRepositoryTests: XCTestCase {
    actor Source: ModelCatalogSource {
        private(set) var calls = 0

        func modelCatalog() async throws -> RemoteModelCatalog {
            calls += 1
            return .init(
                default: .init(provider: "deepseek", model: "deepseek-chat", reasoningEffort: nil),
                routableProviders: ["deepseek"],
                groups: [],
                failures: []
            )
        }
    }

    func testCachesUntilForcedReloadOrInvalidation() async throws {
        let source = Source()
        let repository = ModelCatalogRepository(controller: source)

        _ = try await repository.catalog()
        _ = try await repository.catalog()
        let calls1 = await source.calls
        XCTAssertEqual(calls1, 1)

        _ = try await repository.catalog(forceReload: true)
        let calls2 = await source.calls
        XCTAssertEqual(calls2, 2)

        await repository.invalidate()
        _ = try await repository.catalog()
        let calls3 = await source.calls
        XCTAssertEqual(calls3, 3)
    }
}
