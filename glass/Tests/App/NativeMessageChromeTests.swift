import Foundation
import XCTest

@testable import GlassUI

final class NativeMessageChromeTests: XCTestCase {
    func testClockFormatterUsesCompactSameDayAndDateAwareFallbacks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 8, day: 20, hour: 15, minute: 30, calendar: calendar)

        XCTAssertEqual(
            NativeMessageClockFormatter.label(
                timeMilliseconds: milliseconds(year: 2026, month: 8, day: 20, hour: 4, minute: 28, calendar: calendar),
                now: now,
                calendar: calendar
            ),
            "04:28"
        )
        XCTAssertEqual(
            NativeMessageClockFormatter.label(
                timeMilliseconds: milliseconds(year: 2026, month: 3, day: 9, hour: 4, minute: 28, calendar: calendar),
                now: now,
                calendar: calendar
            ),
            "3/9 04:28"
        )
        XCTAssertEqual(
            NativeMessageClockFormatter.label(
                timeMilliseconds: milliseconds(year: 2025, month: 12, day: 31, hour: 23, minute: 59, calendar: calendar),
                now: now,
                calendar: calendar
            ),
            "2025-12-31 23:59"
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func milliseconds(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Double {
        date(year: year, month: month, day: day, hour: hour, minute: minute, calendar: calendar)
            .timeIntervalSince1970 * 1_000
    }
}
