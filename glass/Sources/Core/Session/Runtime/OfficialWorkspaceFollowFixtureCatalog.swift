import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Reviewed rc.1 `workspace.follow` generations decoded through production wire types.
enum OfficialWorkspaceFollowFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        struct Case: Decodable, Sendable, Identifiable {
            let id: String
            let streams: [[RemoteWorkspaceFollowFrame]]
        }

        let schemaVersion: Int
        let officialSourceCommit: String
        let fixtureRevision: String
        let sourcePaths: [String]
        let cases: [Case]
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(forResource: "official-workspace-follow-fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 1,
              fixture.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.fixtureRevision == "official-a66e470-workspace-follow-r1",
              Set(fixture.sourcePaths) == [
                  "packages/api/workspace-controller/src/types.ts",
                  "packages/api/workspace-controller/src/feed.ts",
              ],
              Set(fixture.cases.map(\.id)) == [
                  "closed-increment-union",
                  "reconnect-replacement-baseline",
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
            case .missingResource: "Official rc.1 workspace.follow fixture resource is missing."
            case .incompatibleFixture: "Official rc.1 workspace.follow fixtures do not match the locked source contract."
            }
        }
    }
}
