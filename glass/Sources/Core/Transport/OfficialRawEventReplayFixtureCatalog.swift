import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Versioned, anonymized event scripts derived from the locked official runtime
/// test builders. Consumers replay the JSON values without accessing any user
/// session, Host credential, or local filesystem state.
enum OfficialRawEventReplayFixtureCatalog {
    struct Fixture: Decodable, Sendable {
        struct Source: Decodable, Sendable {
            let path: String
            let lines: String
            let commit: String
        }

        struct Anonymization: Decodable, Sendable {
            let policy: String
            let forbiddenValueClasses: [String]
        }

        struct ReplayCase: Decodable, Sendable, Identifiable {
            let id: String
            let category: String
            let description: String
            let repeatCount: Int?
            let events: [JSONValue]
        }

        let schemaVersion: Int
        let officialSourceCommit: String
        let fixtureRevision: String
        let source: Source
        let anonymization: Anonymization
        let cases: [ReplayCase]
    }

    static func load() throws -> Fixture {
        guard let url = fixtureBundle.url(forResource: "official-raw-event-replay-fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let requiredCategories: Set<String> = [
            "happy-path", "error", "reconnect", "concurrent", "long-session", "unknown-node",
        ]
        guard fixture.schemaVersion == 1,
              fixture.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.fixtureRevision == "official-528c682e-raw-event-replay-r1",
              fixture.source.commit == OfficialUISpec.Build.sourceCommit,
              fixture.source.path == "packages/client/runtime/tests/event-script.client.ts",
              Set(fixture.cases.map(\.category)).isSuperset(of: requiredCategories),
              Set(fixture.cases.map(\.id)).count == fixture.cases.count,
              fixture.cases.allSatisfy({ !$0.events.isEmpty }),
              fixture.cases.first(where: { $0.category == "long-session" })?.repeatCount ?? 0 >= 1_000,
              Set(fixture.anonymization.forbiddenValueClasses).isSuperset(of: ["credential", "api-key", "private-path", "recorded-user-content"])
        else {
            throw FixtureError.incompatibleFixture
        }
        return fixture
    }

    private static var fixtureBundle: Bundle {
#if SWIFT_PACKAGE
        return .module
#else
        return .main
#endif
    }

    enum FixtureError: LocalizedError {
        case missingResource
        case incompatibleFixture

        var errorDescription: String? {
            switch self {
            case .missingResource: return "Official raw-event replay fixture resource is missing."
            case .incompatibleFixture: return "Official raw-event replay fixture does not match the locked build or anonymization contract."
            }
        }
    }
}
