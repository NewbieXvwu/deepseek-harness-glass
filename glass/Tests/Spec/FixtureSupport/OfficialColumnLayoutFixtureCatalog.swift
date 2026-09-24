import Foundation
@testable import GlassSpec

struct OfficialColumnLayoutFixtureCatalog: Decodable {
    let schemaVersion: Int
    let fixtures: [Fixture]

    struct Fixture: Decodable, Equatable {
        let name: String
        let viewport: CGFloat
        let sidebarPreference: CGFloat
        let detailsPreference: CGFloat
        let expected: Expected
    }

    struct Expected: Decodable, Equatable {
        let sidebar: CGFloat
        let center: CGFloat
        let details: CGFloat
    }

    private static var resourceBundle: Bundle {
#if SWIFT_PACKAGE
        .module
#else
        .main
#endif
    }

    static let catalog: OfficialColumnLayoutFixtureCatalog? = {
        guard let url = resourceBundle.url(
            forResource: "official-column-layout-fixtures",
            withExtension: "json"
        ) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }()
}
