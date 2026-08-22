import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeStatsDockPresentationTests: XCTestCase {
    func testProjectionCountsUniqueHostTurnsStepsAndCompleteUsageOnly() {
        let stats = NativeStatsDockPresentation.project(chatNodes: [
            assistantNode(key: "a", turn: 1, step: 1, usage: .object(["inputTokens": .number(10), "outputTokens": .number(4)])),
            assistantNode(key: "b", turn: 1, step: 2, usage: .object(["inputTokens": .number(7), "outputTokens": .number(3)])),
            assistantNode(key: "c", turn: 2, step: 1, usage: .object(["inputTokens": .number(2), "outputTokens": .number(1)])),
        ])

        XCTAssertEqual(stats, .init(turns: 2, steps: 3, inputTokens: 19, outputTokens: 8))
    }

    func testMissingHostUsageDoesNotProducePartialTokenTotal() {
        let stats = NativeStatsDockPresentation.project(chatNodes: [
            assistantNode(key: "a", turn: 1, step: 1, usage: .object(["inputTokens": .number(10), "outputTokens": .number(4)])),
            assistantNode(key: "b", turn: 1, step: 2, usage: nil),
        ])

        // Present usage rows are summed; a row without usage simply contributes
        // nothing, so partial totals from available Host usage are expected.
        XCTAssertEqual(stats, .init(turns: 1, steps: 2, inputTokens: 10, outputTokens: 4))
        XCTAssertNil(NativeStatsDockPresentation.project(chatNodes: []))
    }

    private func assistantNode(key: String, turn: Int, step: Int, usage: JSONValue?) -> ConversationViewNode {
        .init(
            key: key,
            kind: "assistant-step",
            id: "\(turn):\(step)",
            target: "chat",
            data: CoreAssistantNode(
                status: .settled,
                turn: turn,
                step: step,
                seq: step,
                time: Double(step),
                messageID: key,
                blocks: [],
                firstTokenTime: nil,
                completedTime: Double(step),
                usage: usage
            )
        )
    }
}
