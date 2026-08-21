import XCTest
@testable import GlassCore

final class GhostPlaneBridgeWireEncoderTests: XCTestCase {
    func testKeyboardRoundTripsThroughFixedWireEnvelope() throws {
        let message = GhostPlaneBridgeMessage(
            documentEpoch: 1,
            sequence: 2,
            direction: .nativeToPlane,
            event: .keyboard(.init(phase: .down, key: "Enter", code: "Enter", location: 0, modifiers: [.shift], isRepeat: false, isComposing: false))
        )
        XCTAssertEqual(try GhostPlaneBridgeWireDecoder.decode(GhostPlaneBridgeWireEncoder.encode(message)), message)
    }

    func testDragRoundTripsThroughFixedWireEnvelope() throws {
        let message = GhostPlaneBridgeMessage(
            documentEpoch: 3,
            sequence: 4,
            direction: .nativeToPlane,
            event: .drag(.init(phase: .drop, operation: .copy, attachmentIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!], x: 1.25, y: -2.5))
        )
        XCTAssertEqual(try GhostPlaneBridgeWireDecoder.decode(GhostPlaneBridgeWireEncoder.encode(message)), message)
    }
}
