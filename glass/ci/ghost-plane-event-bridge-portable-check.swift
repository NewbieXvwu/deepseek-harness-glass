import Foundation

@main
struct GhostPlaneEventBridgePortableCheck {
    static func main() throws {
        let keyboard = GhostPlaneBridgeEvent.keyboard(.init(
            phase: .down,
            key: "Enter",
            code: "Enter",
            location: 0,
            modifiers: [.shift],
            isRepeat: false,
            isComposing: false
        ))
        var fence = GhostPlaneEventBridgeFence(documentEpoch: 4, echoWindow: 2)
        let first = try expect(fence.emitNative(keyboard))
        let second = try expect(fence.emitNative(keyboard))
        let third = try expect(fence.emitNative(keyboard))
        try equal([first.sequence, second.sequence, third.sequence], [1, 2, 3], "native sequence")
        try equal(first.documentEpoch, 4, "native epoch")
        try equal(first.direction, .nativeToPlane, "native direction")
        try equal(
            fence.receivePlane(.init(
                documentEpoch: 4, sequence: 1, direction: .planeToNative,
                echoOfNativeSequence: 1, event: keyboard
            )),
            .rejectedUnknownEcho,
            "evicted echo"
        )
        try equal(
            fence.receivePlane(.init(
                documentEpoch: 4, sequence: 2, direction: .planeToNative,
                echoOfNativeSequence: 2, event: keyboard
            )),
            .suppressNativeEcho,
            "known native echo"
        )

        var inbound = GhostPlaneEventBridgeFence(documentEpoch: 9)
        try equal(
            inbound.receivePlane(.init(documentEpoch: 8, sequence: 1, direction: .planeToNative, event: keyboard)),
            .rejectedWrongEpoch(expected: 9, received: 8),
            "stale document"
        )
        try equal(
            inbound.receivePlane(.init(documentEpoch: 9, sequence: 1, direction: .nativeToPlane, event: keyboard)),
            .rejectedWrongDirection,
            "wrong direction"
        )
        try equal(
            inbound.receivePlane(.init(documentEpoch: 9, sequence: 2, direction: .planeToNative, event: keyboard)),
            .deliver(keyboard),
            "page keyboard delivery"
        )
        try equal(
            inbound.receivePlane(.init(documentEpoch: 9, sequence: 2, direction: .planeToNative, event: keyboard)),
            .rejectedStaleSequence(lastReceived: 2, received: 2),
            "duplicate page event"
        )

        let selection = GhostPlaneBridgeEvent.selection(.init(
            anchorID: "ghost-chat-anchor-message:1", anchorOffset: 0,
            focusID: "ghost-chat-anchor-message:2", focusOffset: 3, isCollapsed: false
        ))
        let paste = GhostPlaneBridgeEvent.imagePaste(.init(
            attachmentID: UUID(), suggestedName: "pasted.png", mediaType: "image/png"
        ))
        let drag = GhostPlaneBridgeEvent.drag(.init(
            phase: .drop, operation: .copy, attachmentIDs: [UUID()], x: 1, y: 2
        ))
        _ = try expect(inbound.emitNative(selection))
        _ = try expect(inbound.emitNative(paste))
        _ = try expect(inbound.emitNative(drag))
        let unsafeSelection = GhostPlaneBridgeEvent.selection(.init(
            anchorID: "plugin-node", anchorOffset: 0,
            focusID: "plugin-node", focusOffset: 0, isCollapsed: true
        ))
        let unsafeDrag = GhostPlaneBridgeEvent.drag(.init(
            phase: .drop, operation: .copy, attachmentIDs: [UUID()], x: .infinity, y: 0
        ))
        try check(inbound.emitNative(unsafeSelection) == nil, "unsafe selection must reject")
        try check(inbound.emitNative(unsafeDrag) == nil, "non-finite drag must reject")
        print("ghost plane event bridge portable check passed")
    }

    private static func expect<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure("required result was nil") }
        return value
    }

    private static func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else { throw CheckFailure("\(label): expected \(expected), got \(actual)") }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message) }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
