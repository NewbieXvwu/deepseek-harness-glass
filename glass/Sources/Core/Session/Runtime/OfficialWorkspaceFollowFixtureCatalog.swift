import Foundation

/// `workspace.follow` generations decoded through production wire types.
enum OfficialWorkspaceFollowFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        struct Case: Decodable, Sendable, Identifiable {
            let id: String
            let streams: [[RemoteWorkspaceFollowFrame]]
        }

        let schemaVersion: Int
        let cases: [Case]
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(forResource: "official-workspace-follow-fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 1,
              !fixture.cases.isEmpty,
              Set(fixture.cases.map(\.id)).count == fixture.cases.count,
              fixture.cases.allSatisfy({ !$0.streams.isEmpty && $0.streams.allSatisfy({ !$0.isEmpty }) })
        else {
            throw FixtureError.incompatibleFixture
        }
        return fixture
    }

    private static var fixtureBundle: Bundle {
#if SWIFT_PACKAGE
        .module
#else
        .main
#endif
    }

    enum FixtureError: LocalizedError {
        case missingResource
        case incompatibleFixture

        var errorDescription: String? {
            switch self {
            case .missingResource: "Workspace follow fixture resource is missing."
            case .incompatibleFixture: "Workspace follow fixture is malformed or empty."
            }
        }
    }
}
