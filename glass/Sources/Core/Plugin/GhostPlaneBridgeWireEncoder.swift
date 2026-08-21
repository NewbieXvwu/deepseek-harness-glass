import Foundation

/// Fixed JSON encoder for native-to-plane typed bridge messages. The payload is
/// intentionally symmetrical with `GhostPlaneBridgeWireDecoder`; no platform
/// object, callback, selector, HTML, bytes or executable source is representable.
public enum GhostPlaneBridgeWireEncoder {
    public static func encode(_ message: GhostPlaneBridgeMessage) throws -> Data {
        try JSONEncoder().encode(Envelope(message))
    }

    private struct Envelope: Encodable {
        let documentEpoch: UInt64
        let sequence: UInt64
        let direction: String
        let echoOfNativeSequence: UInt64?
        let event: Event

        init(_ message: GhostPlaneBridgeMessage) {
            documentEpoch = message.documentEpoch
            sequence = message.sequence
            direction = message.direction == .nativeToPlane ? "nativeToPlane" : "planeToNative"
            echoOfNativeSequence = message.echoOfNativeSequence
            event = .init(message.event)
        }
    }

    private struct Event: Encodable {
        let kind: String
        let phase: String?
        let key: String?
        let code: String?
        let location: UInt8?
        let modifiers: UInt8?
        let isRepeat: Bool?
        let isComposing: Bool?
        let attachmentID: String?
        let suggestedName: String?
        let mediaType: String?
        let anchorID: String?
        let anchorOffset: UInt32?
        let focusID: String?
        let focusOffset: UInt32?
        let isCollapsed: Bool?
        let dragPhase: String?
        let operation: String?
        let attachmentIDs: [String]?
        let x: Double?
        let y: Double?

        init(_ event: GhostPlaneBridgeEvent) {
            switch event {
            case .keyboard(let value):
                kind = "keyboard"; phase = value.phase.rawValue; key = value.key; code = value.code
                location = value.location; modifiers = value.modifiers.rawValue; isRepeat = value.isRepeat; isComposing = value.isComposing
                attachmentID = nil; suggestedName = nil; mediaType = nil; anchorID = nil; anchorOffset = nil; focusID = nil; focusOffset = nil; isCollapsed = nil; dragPhase = nil; operation = nil; attachmentIDs = nil; x = nil; y = nil
            case .imagePaste(let value):
                kind = "imagePaste"; attachmentID = value.attachmentID.uuidString; suggestedName = value.suggestedName; mediaType = value.mediaType
                phase = nil; key = nil; code = nil; location = nil; modifiers = nil; isRepeat = nil; isComposing = nil; anchorID = nil; anchorOffset = nil; focusID = nil; focusOffset = nil; isCollapsed = nil; dragPhase = nil; operation = nil; attachmentIDs = nil; x = nil; y = nil
            case .selection(let value):
                kind = "selection"; anchorID = value.anchorID; anchorOffset = value.anchorOffset; focusID = value.focusID; focusOffset = value.focusOffset; isCollapsed = value.isCollapsed
                phase = nil; key = nil; code = nil; location = nil; modifiers = nil; isRepeat = nil; isComposing = nil; attachmentID = nil; suggestedName = nil; mediaType = nil; dragPhase = nil; operation = nil; attachmentIDs = nil; x = nil; y = nil
            case .drag(let value):
                kind = "drag"; dragPhase = value.phase.rawValue; operation = value.operation.rawValue; attachmentIDs = value.attachmentIDs.map(\.uuidString); x = value.x; y = value.y
                phase = nil; key = nil; code = nil; location = nil; modifiers = nil; isRepeat = nil; isComposing = nil; attachmentID = nil; suggestedName = nil; mediaType = nil; anchorID = nil; anchorOffset = nil; focusID = nil; focusOffset = nil; isCollapsed = nil
            }
        }
    }
}
