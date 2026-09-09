import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Reviewed rc.1 `session.control` generations decoded through production wire types.
enum OfficialSessionControlFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        struct Case: Decodable, Sendable, Identifiable {
            let id: String
            let streams: [[RemoteSessionControlFrame]]
        }

        let schemaVersion: Int
        let officialSourceCommit: String
        let fixtureRevision: String
        let sourcePaths: [String]
        let cases: [Case]
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(forResource: "official-session-control-fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 1,
              fixture.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.fixtureRevision == "official-a66e470-session-control-r1",
              Set(fixture.sourcePaths) == [
                  "packages/api/session-controller/src/types.ts",
                  "packages/api/session-controller/src/control.ts",
              ],
              Set(fixture.cases.map(\.id)) == [
                  "replacement-deltas-and-reconnect",
                  "empty-opening-baseline",
              ],
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
            case .missingResource: "Official rc.1 session.control fixture resource is missing."
            case .incompatibleFixture: "Official rc.1 session.control fixtures do not match the locked source contract."
            }
        }
    }
}
