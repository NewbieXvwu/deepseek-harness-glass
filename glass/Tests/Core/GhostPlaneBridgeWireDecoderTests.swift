import XCTest
@testable import GlassCore

final class GhostPlaneBridgeWireDecoderTests: XCTestCase {
    func testDecodesPlaneKeyboardAndSelectionMessages() throws {
        let keyboard = try GhostPlaneBridgeWireDecoder.decode(Data("""
        {"documentEpoch":3,"sequence":8,"direction":"planeToNative","event":{"kind":"keyboard","phase":"down","key":"Enter","code":"Enter","location":0,"modifiers":1,"isRepeat":false,"isComposing":false}}
        """.utf8))
        XCTAssertEqual(keyboard.direction, .planeToNative)
        XCTAssertEqual(keyboard.event, .keyboard(.init(phase: .down, key: "Enter", code: "Enter", location: 0, modifiers: [.shift], isRepeat: false, isComposing: false)))
        let selection = try GhostPlaneBridgeWireDecoder.decode(Data("""
        {"documentEpoch":3,"sequence":9,"direction":"planeToNative","event":{"kind":"selection","anchorID":"ghost-chat","anchorOffset":1,"focusID":"ghost-chat","focusOffset":1,"isCollapsed":true}}
        """.utf8))
        XCTAssertEqual(selection.event, .selection(.init(anchorID: "ghost-chat", anchorOffset: 1, focusID: "ghost-chat", focusOffset: 1, isCollapsed: true)))
    }

    func testRejectsUnknownWireAndInvalidDrag() {
        XCTAssertThrowsError(try GhostPlaneBridgeWireDecoder.decode(Data("{".utf8)))
        XCTAssertThrowsError(try GhostPlaneBridgeWireDecoder.decode(Data("{\"documentEpoch\":1,\"sequence\":1,\"direction\":\"bad\",\"event\":{\"kind\":\"keyboard\"}}".utf8)))
        XCTAssertThrowsError(try GhostPlaneBridgeWireDecoder.decode(Data("{\"documentEpoch\":1,\"sequence\":1,\"direction\":\"planeToNative\",\"event\":{\"kind\":\"drag\",\"dragPhase\":\"drop\",\"operation\":\"copy\",\"attachmentIDs\":[\"bad\"],\"x\":0,\"y\":0}}".utf8)))
    }
}
