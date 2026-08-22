import XCTest

@testable import GlassCore

final class NativeClipboardCopyFeedbackTests: XCTestCase {
    func testAcceptedWriteTransitionsIdleToCopiedAndExpiryReturnsIdle() {
        XCTAssertTrue(NativeClipboardCopyFeedback.acceptsActivation(state: .idle))
        let copied = NativeClipboardCopyFeedback.resolveWrite(state: .idle, accepted: true)
        XCTAssertEqual(copied, .copied)
        XCTAssertFalse(NativeClipboardCopyFeedback.acceptsActivation(state: copied))
        XCTAssertEqual(NativeClipboardCopyFeedback.resolveExpiry(state: copied), .idle)
    }

    func testRefusedWriteAndRepeatActivationNeverClaimCopySuccess() {
        XCTAssertEqual(NativeClipboardCopyFeedback.resolveWrite(state: .idle, accepted: false), .idle)
        XCTAssertEqual(NativeClipboardCopyFeedback.resolveWrite(state: .copied, accepted: true), .copied)
        XCTAssertEqual(NativeClipboardCopyFeedback.resolveWrite(state: .copied, accepted: false), .copied)
        XCTAssertEqual(NativeClipboardCopyFeedback.resolveExpiry(state: .idle), .idle)
    }
}
