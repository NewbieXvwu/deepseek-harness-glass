import Foundation

/// Session journal wire fixtures decoded directly into production Remote/session types.
enum OfficialSessionJournalFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        struct Case: Decodable, Sendable, Identifiable {
            struct Expected: Decodable, Sendable {
                let openingCut: Int
                let appliedThrough: Int
                let firstSeq: Int?
                let recordCount: Int
                let hasMore: Bool
                let projectionAsOfSeq: Int
                let projectionKeys: [String]
                let replayDeduplicatedCount: Int
            }

            let id: String
            let address: SessionAddress
            let opening: RemoteSessionFollowFrame
            let liveEvents: [RemoteSessionWireEvent]
            let olderPages: [RemoteSessionPageValue]
            let repairOpening: RemoteSessionFollowFrame?
            let replayEvents: [RemoteSessionWireEvent]
            let expected: Expected
        }

        let schemaVersion: Int
        let cases: [Case]
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(forResource: "official-session-journal-fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 2,
              !fixture.cases.isEmpty,
              Set(fixture.cases.map(\.id)).count == fixture.cases.count
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
            case .missingResource: "Session journal fixture resource is missing."
            case .incompatibleFixture: "Session journal fixture is malformed or empty."
            }
        }
    }
}
