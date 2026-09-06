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
        XCTAssertEqual(await source.calls, 1)

        _ = try await repository.catalog(forceReload: true)
        XCTAssertEqual(await source.calls, 2)

        await repository.invalidate()
        _ = try await repository.catalog()
        XCTAssertEqual(await source.calls, 3)
    }
}
