@testable import GlassCore
import XCTest

final class GhostPlaneEventBridgeTests: XCTestCase {
    func testNativeEventGetsCurrentEpochAndBoundedEchoIdentity() throws {
        var fence = GhostPlaneEventBridgeFence(documentEpoch: 4, echoWindow: 2)
        let event = keyboard()

        let first = try XCTUnwrap(fence.emitNative(event))
        let second = try XCTUnwrap(fence.emitNative(event))
        let third = try XCTUnwrap(fence.emitNative(event))

        XCTAssertEqual(first.documentEpoch, 4)
        XCTAssertEqual(first.direction, .nativeToPlane)
        XCTAssertEqual([first.sequence, second.sequence, third.sequence], [1, 2, 3])
        XCTAssertEqual(
            fence.receivePlane(.init(
                documentEpoch: 4,
                sequence: 1,
                direction: .planeToNative,
                echoOfNativeSequence: 1,
                event: event
            )),
            .rejectedUnknownEcho
        )
        XCTAssertEqual(
            fence.receivePlane(.init(
                documentEpoch: 4,
                sequence: 2,
                direction: .planeToNative,
                echoOfNativeSequence: 2,
                event: event
            )),
            .suppressNativeEcho
        )
    }

    func testPlaneEventRequiresCurrentEpochDirectionAndStrictSequence() {
        var fence = GhostPlaneEventBridgeFence(documentEpoch: 9)
        let event = keyboard()

        XCTAssertEqual(
            fence.receivePlane(.init(documentEpoch: 8, sequence: 1, direction: .planeToNative, event: event)),
            .rejectedWrongEpoch(expected: 9, received: 8)
        )
        XCTAssertEqual(
            fence.receivePlane(.init(documentEpoch: 9, sequence: 1, direction: .nativeToPlane, event: event)),
            .rejectedWrongDirection
        )
        XCTAssertEqual(
            fence.receivePlane(.init(documentEpoch: 9, sequence: 2, direction: .planeToNative, event: event)),
            .deliver(event)
        )
        XCTAssertEqual(
            fence.receivePlane(.init(documentEpoch: 9, sequence: 2, direction: .planeToNative, event: event)),
            .rejectedStaleSequence(lastReceived: 2, received: 2)
        )
    }

    func testContractsRejectUnsafeEventShapesButRetainAllFourBridgeKinds() {
        var fence = GhostPlaneEventBridgeFence(documentEpoch: 1)
        let validSelection = GhostPlaneBridgeEvent.selection(.init(
            anchorID: "ghost-chat-anchor-message:1",
            anchorOffset: 1,
            focusID: "ghost-chat-anchor-message:2",
            focusOffset: 3,
            isCollapsed: false
        ))
        let validPaste = GhostPlaneBridgeEvent.imagePaste(.init(
            attachmentID: UUID(),
            suggestedName: "pasted.png",
            mediaType: "image/png"
        ))
        let validDrag = GhostPlaneBridgeEvent.drag(.init(
            phase: .drop,
            operation: .copy,
            attachmentIDs: [UUID()],
            x: 10.5,
            y: -3
        ))
        XCTAssertNotNil(fence.emitNative(validSelection))
        XCTAssertNotNil(fence.emitNative(validPaste))
        XCTAssertNotNil(fence.emitNative(validDrag))

        let invalidSelection = GhostPlaneBridgeEvent.selection(.init(
            anchorID: "other-node",
            anchorOffset: 0,
            focusID: "other-node",
            focusOffset: 0,
            isCollapsed: true
        ))
        let invalidDrag = GhostPlaneBridgeEvent.drag(.init(
            phase: .drop,
            operation: .copy,
            attachmentIDs: [UUID(), UUID()],
            x: .infinity,
            y: 0
        ))
        XCTAssertNil(fence.emitNative(invalidSelection))
        XCTAssertNil(fence.emitNative(invalidDrag))
    }

    private func keyboard() -> GhostPlaneBridgeEvent {
        .keyboard(.init(
            phase: .down,
            key: "Enter",
            code: "Enter",
            location: 0,
            modifiers: [.shift],
            isRepeat: false,
            isComposing: false
        ))
    }
}
