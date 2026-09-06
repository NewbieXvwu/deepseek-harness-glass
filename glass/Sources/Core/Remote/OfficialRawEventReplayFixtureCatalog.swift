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

    /// Expands a deterministic template without reaching a Host or inventing
    /// payload values. Each iteration receives unique sequence, time, turn, and
    /// fixture-local identifiers so a reducer can replay it as a real long
    /// conversation rather than a duplicate-event microbenchmark.
    static func expandedEvents(for replay: Fixture.ReplayCase) -> [JSONValue] {
        let repeats = replay.repeatCount ?? 1
        guard repeats > 1 else { return replay.events }
        let stride = (replay.events.map { $0.objectValue?["seq"]?.numberValue ?? 0 }.max() ?? 0)
        return (0 ..< repeats).flatMap { iteration in
            replay.events.map { expand($0, iteration: iteration, sequenceStride: stride) }
        }
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
              fixture.fixtureRevision == "official-a66e470-raw-event-replay-r1",
              fixture.source.commit == OfficialUISpec.Build.sourceCommit,
              fixture.source.path == "packages/api/session-controller/tests/event-script.client.ts",
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

    private static func expand(_ value: JSONValue, iteration: Int, sequenceStride: Double) -> JSONValue {
        switch value {
        case let .array(values):
            return .array(values.map { expand($0, iteration: iteration, sequenceStride: sequenceStride) })
        case let .object(object):
            var expanded = object.mapValues { expand($0, iteration: iteration, sequenceStride: sequenceStride) }
            if let sequence = object["seq"]?.numberValue {
                expanded["seq"] = .number(sequence + Double(iteration) * sequenceStride)
            }
            if let time = object["time"]?.numberValue {
                expanded["time"] = .number(time + Double(iteration) * sequenceStride)
            }
            if let turn = object["turn"]?.numberValue {
                expanded["turn"] = .number(turn + Double(iteration))
            }
            return .object(expanded)
        case let .string(value):
            return .string(value.hasPrefix("fixture-long-") ? "\(value)-\(iteration + 1)" : value)
        case .null, .bool, .number:
            return value
        }
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
