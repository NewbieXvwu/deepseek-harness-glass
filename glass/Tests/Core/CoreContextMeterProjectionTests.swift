import XCTest
@testable import GlassCore

final class CoreContextMeterProjectionTests: XCTestCase {
    func testProjectedContextUsageWinsOverOlderPressureAfterCompaction() {
        let state = CoreContextMeterState.value(projection: .object([
            "pressureTokens": .number(32_000),
            "projectedTokens": .number(3_000),
            "contextWindow": .number(128_000),
        ]))

        XCTAssertEqual(state, .init(usedTokens: 3_000, contextWindow: 128_000, percent: 2))
    }

    func testPressureFallbackRoundsAndClampsLikeOfficialContextOccupancy() {
        XCTAssertEqual(
            CoreContextMeterState.value(projection: .object([
                "pressureTokens": .number(32_000),
                "contextWindow": .number(128_000),
            ])),
            .init(usedTokens: 32_000, contextWindow: 128_000, percent: 25)
        )
        XCTAssertEqual(
            CoreContextMeterState.value(projection: .object([
                "pressureTokens": .number(256_000),
                "contextWindow": .number(128_000),
            ]))?.percent,
            100
        )
    }

    func testContextBreakdownRequiresAllThreeHostCompositionValues() {
        XCTAssertEqual(
            CoreContextMeterBreakdown.value(projection: .object([
                "systemTokens": .number(1_000),
                "toolsTokens": .number(2_000),
                "messageTokens": .number(3_000),
            ])),
            .init(systemTokens: 1_000, toolsTokens: 2_000, messageTokens: 3_000)
        )
        XCTAssertNil(CoreContextMeterBreakdown.value(projection: .object([
            "systemTokens": .number(1_000),
            "toolsTokens": .number(2_000),
        ])))
        XCTAssertNil(CoreContextMeterBreakdown.value(projection: .object([
            "systemTokens": .number(1_000),
            "toolsTokens": .number(2_000),
            "messageTokens": .number(-3_000),
        ])))
    }

    @MainActor
    func testContextMetersReadOnlyCurrentHostProjectionStoreValues() {
        let store = SessionProjectionStore()
        store.apply(
            sessionID: "session-a",
            key: "contextPressure",
            value: .object([
                "projectedTokens": .number(6_400),
                "contextWindow": .number(128_000),
            ]),
            seq: 42
        )
        store.apply(
            sessionID: "session-a",
            key: "contextBreakdown",
            value: .object([
                "systemTokens": .number(400),
                "toolsTokens": .number(1_000),
                "messageTokens": .number(5_000),
            ]),
            seq: 42
        )

        XCTAssertEqual(
            CoreContextMeterState.value(from: store, sessionID: "session-a"),
            .init(usedTokens: 6_400, contextWindow: 128_000, percent: 5)
        )
        XCTAssertEqual(
            CoreContextMeterBreakdown.value(from: store, sessionID: "session-a"),
            .init(systemTokens: 400, toolsTokens: 1_000, messageTokens: 5_000)
        )
        XCTAssertNil(CoreContextMeterState.value(from: store, sessionID: "other-session"))
    }

    func testMalformedOrCapacitylessContextPressureDoesNotInventMeter() {
        XCTAssertNil(CoreContextMeterState.value(projection: .object([
            "pressureTokens": .number(0),
        ])))
        XCTAssertNil(CoreContextMeterState.value(projection: .object([
            "pressureTokens": .number(1),
            "contextWindow": .number(0),
        ])))
        XCTAssertNil(CoreContextMeterState.value(projection: .object([
            "pressureTokens": .number(-1),
            "contextWindow": .number(128_000),
        ])))
        XCTAssertNil(CoreContextMeterState.value(projection: .object([
            "pressureTokens": .number(1.5),
            "contextWindow": .number(128_000),
        ])))
    }
}
