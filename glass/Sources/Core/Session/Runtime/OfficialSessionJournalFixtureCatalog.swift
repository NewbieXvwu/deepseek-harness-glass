import Foundation

/// Reviewed rc.1 Session journal wire fixtures. The JSON decodes directly into
/// production Remote/session types so fixture drift cannot hide behind a test DTO.
enum OfficialSessionJournalFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        struct Case: Decodable, Sendable, Identifiable {
            struct Expected: Decodable, Sendable {
                let openingCut: Int
                let appliedThrough: Int
                let firstSeq: Int?
                let recordCount: Int
                let hasMore: Bool
            }

            let id: String
            let address: SessionAddress
            let opening: RemoteSessionFollowFrame
            let liveEvents: [RemoteSessionWireEvent]
            let olderPages: [RemoteSessionPageValue]
            let expected: Expected
        }

        let schemaVersion: Int
        let officialSourceCommit: String
        let fixtureRevision: String
        let sourcePaths: [String]
        let cases: [Case]
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(forResource: "official-session-journal-fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let expectedCases: Set<String> = [
            "packed-opening-live-prepend",
            "direct-subagent-empty",
            "unfinished-assistant-long-tail",
        ]
        let expectedSources: Set<String> = [
            "packages/api/session-controller/src/types.ts",
            "packages/api/session-controller/src/history.ts",
            "packages/api/session-controller/src/client/sessions/history-records.ts",
        ]
        guard fixture.schemaVersion == 1,
              fixture.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.fixtureRevision == "official-a66e470-session-journal-r1",
              Set(fixture.sourcePaths) == expectedSources,
              Set(fixture.cases.map(\.id)) == expectedCases
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
            case .missingResource: "Official rc.1 Session journal fixture resource is missing."
            case .incompatibleFixture: "Official rc.1 Session journal fixtures do not match the locked source contract."
            }
        }
    }
}
