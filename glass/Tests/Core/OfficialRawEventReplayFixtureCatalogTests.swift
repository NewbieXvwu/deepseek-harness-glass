import XCTest

@testable import GlassCore
@testable import GlassSpec

final class OfficialRawEventReplayFixtureCatalogTests: XCTestCase {
    func testLockedAnonymizedReplayCatalogCoversRequiredOfflineScenarios() throws {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()

        XCTAssertEqual(fixture.officialSourceCommit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(fixture.source.commit, OfficialUISpec.Build.sourceCommit)
        XCTAssertEqual(fixture.source.path, "packages/client/runtime/tests/event-script.client.ts")
        XCTAssertEqual(Set(fixture.cases.map(\.category)), [
            "happy-path", "error", "reconnect", "concurrent", "long-session", "unknown-node",
        ])
        XCTAssertEqual(fixture.cases.first(where: { $0.category == "long-session" })?.repeatCount, 1_000)

        for replay in fixture.cases {
            XCTAssertFalse(replay.events.isEmpty, "\(replay.id) must be replayable offline")
            for event in replay.events {
                let object = tryUnwrap(event.objectValue)
                XCTAssertNotNil(object["seq"]?.numberValue, "\(replay.id) event requires a deterministic sequence")
                XCTAssertNotNil(object["time"]?.numberValue, "\(replay.id) event requires a deterministic timestamp")
                XCTAssertFalse(object["type"]?.stringValue?.isEmpty ?? true, "\(replay.id) event requires an official type")
            }
        }
    }

    func testLongSessionTemplateExpandsIntoContinuousUniqueReplayEvents() throws {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = tryUnwrap(fixture.cases.first(where: { $0.id == "long-session-template" }))
        let events = OfficialRawEventReplayFixtureCatalog.expandedEvents(for: replay)
        let objects = try events.map { try tryUnwrap($0.objectValue) }
        let sequences = try objects.map { try tryUnwrap($0["seq"]?.numberValue) }
        let userIDs = objects.compactMap { $0["data"]?.objectValue?["id"]?.stringValue }

        XCTAssertEqual(events.count, 4_000)
        XCTAssertEqual(sequences, Array(1 ... 4_000).map(Double.init))
        XCTAssertEqual(userIDs.count, 1_000)
        XCTAssertEqual(Set(userIDs).count, 1_000)
        XCTAssertEqual(userIDs.first, "fixture-long-user-1")
        XCTAssertEqual(userIDs.last, "fixture-long-user-1000")
    }

    func testReplayEventPayloadsContainNoCapturedCredentialOrPrivatePathMarkers() throws {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let forbidden = ["/Users/", "/home/", "BEGIN PRIVATE", "api_key", "sk-"]

        for replay in fixture.cases {
            let encoded = try JSONEncoder().encode(replay.events)
            let payload = String(decoding: encoded, as: UTF8.self)
            for marker in forbidden {
                XCTAssertFalse(payload.localizedCaseInsensitiveContains(marker), "\(replay.id) contains disallowed captured data marker \(marker)")
            }
        }
    }
}
