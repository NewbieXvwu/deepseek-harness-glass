import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeAssistantTextPresentationTests: XCTestCase {
    func testReasoningBlocksNeverEnterVisibleAssistantText() {
        let assistant = assistant(blocks: [
            block(.reasoning, "private reasoning"),
            block(.text, "safe answer"),
            block(.reasoning, "more private reasoning"),
        ])

        XCTAssertEqual(NativeAssistantTextPresentation.visibleText(assistant), "safe answer")
    }

    func testReasoningOnlyAssistantHasNoVisibleText() {
        XCTAssertEqual(
            NativeAssistantTextPresentation.visibleText(assistant(blocks: [block(.reasoning, "private reasoning")])),
            ""
        )
    }

    private func assistant(blocks: [ConversationContentBlock]) -> CoreAssistantNode {
        .init(
            status: .settled,
            turn: 1,
            step: 1,
            seq: 1,
            time: 1,
            messageID: "assistant-1",
            blocks: blocks,
            firstTokenTime: nil,
            completedTime: 1,
            usage: nil
        )
    }

    private func block(_ kind: ConversationContentBlock.Kind, _ text: String) -> ConversationContentBlock {
        .init(kind: kind, text: text, callID: nil, name: nil, argumentsRaw: nil, raw: .null)
    }
}
