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
