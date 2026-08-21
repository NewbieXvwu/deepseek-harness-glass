import Foundation
import XCTest

@testable import GlassCore
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
                timeMilliseconds: milliseconds(year: 2026, month: 8, day: 19, hour: 23, minute: 59, calendar: calendar),
                now: now,
                calendar: calendar
            ),
            "8/19 23:59"
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

    func testCopyPresentationUsesOnlyDurableHostMessageIDs() {
        let user = CoreUserMessageNode(
            kind: .user,
            seq: 1,
            time: 1,
            messageID: "host-user-1",
            content: [],
            sourceKind: "user",
            sourcePlugin: nil
        )
        let context = CoreUserMessageNode(
            kind: .context,
            seq: 2,
            time: 2,
            messageID: "host-context-2",
            content: [],
            sourceKind: "context",
            sourcePlugin: nil
        )
        let settled = CoreAssistantNode(
            status: .settled,
            turn: 1,
            step: 1,
            seq: 3,
            time: 3,
            messageID: "host-assistant-3",
            blocks: [],
            firstTokenTime: nil,
            completedTime: 3,
            usage: nil
        )
        let streaming = CoreAssistantNode(
            status: .running,
            turn: 1,
            step: 1,
            seq: 4,
            time: 4,
            messageID: nil,
            blocks: [],
            firstTokenTime: nil,
            completedTime: nil,
            usage: nil
        )

        XCTAssertEqual(NativeMessageCopyPresentation.hostMessageID(for: conversationNode(data: user)), "host-user-1")
        XCTAssertNil(NativeMessageCopyPresentation.hostMessageID(for: conversationNode(data: context)))
        XCTAssertEqual(NativeMessageCopyPresentation.hostMessageID(for: settled), "host-assistant-3")
        XCTAssertNil(NativeMessageCopyPresentation.hostMessageID(for: streaming))
    }

    private func conversationNode(data: Any) -> ConversationViewNode {
        .init(key: "fixture", kind: "fixture", id: "fixture", target: "chat", data: data)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func milliseconds(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Double {
        date(year: year, month: month, day: day, hour: hour, minute: minute, calendar: calendar)
            .timeIntervalSince1970 * 1_000
    }
}
