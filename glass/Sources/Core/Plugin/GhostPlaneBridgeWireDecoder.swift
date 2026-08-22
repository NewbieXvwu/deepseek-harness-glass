import Foundation

/// Strict JSON-only decoder for `WKScriptMessage` payload bytes. It terminates
/// the wire boundary before the event fence: arbitrary page objects, callbacks
/// and non-JSON values cannot become bridge events.
public enum GhostPlaneBridgeWireDecoder {
    public enum Rejection: Error, Equatable, Sendable {
        case malformed
        case unknownDirection
        case unknownEventKind
        case invalidEvent
    }

    public static func decode(_ data: Data) throws -> GhostPlaneBridgeMessage {
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw Rejection.malformed }
        guard let direction = GhostPlaneBridgeMessage.Direction(wire: envelope.direction) else { throw Rejection.unknownDirection }
        let event: GhostPlaneBridgeEvent
        switch envelope.event.kind {
        case "keyboard":
            guard let phase = GhostPlaneBridgeEvent.Keyboard.Phase(rawValue: envelope.event.phase ?? ""),
                  let key = envelope.event.key, let code = envelope.event.code,
                  let location = envelope.event.location, let modifiers = envelope.event.modifiers,
                  let isRepeat = envelope.event.isRepeat, let isComposing = envelope.event.isComposing
            else { throw Rejection.invalidEvent }
            event = .keyboard(.init(phase: phase, key: key, code: code, location: location, modifiers: .init(rawValue: modifiers), isRepeat: isRepeat, isComposing: isComposing))
        case "imagePaste":
            guard let rawID = envelope.event.attachmentID, let id = UUID(uuidString: rawID), let name = envelope.event.suggestedName, let mediaType = envelope.event.mediaType else { throw Rejection.invalidEvent }
            event = .imagePaste(.init(attachmentID: id, suggestedName: name, mediaType: mediaType))
        case "selection":
            guard let anchorID = envelope.event.anchorID, let anchorOffset = envelope.event.anchorOffset,
                  let focusID = envelope.event.focusID, let focusOffset = envelope.event.focusOffset,
                  let isCollapsed = envelope.event.isCollapsed
            else { throw Rejection.invalidEvent }
            event = .selection(.init(anchorID: anchorID, anchorOffset: anchorOffset, focusID: focusID, focusOffset: focusOffset, isCollapsed: isCollapsed))
        case "drag":
            guard let phase = envelope.event.dragPhase.flatMap(GhostPlaneBridgeEvent.Drag.Phase.init(rawValue:)),
                  let operation = envelope.event.operation.flatMap(GhostPlaneBridgeEvent.Drag.Operation.init(rawValue:)),
                  let rawIDs = envelope.event.attachmentIDs,
                  let x = envelope.event.x, let y = envelope.event.y, x.isFinite, y.isFinite
            else { throw Rejection.invalidEvent }
            var attachmentIDs: [UUID] = []
            attachmentIDs.reserveCapacity(rawIDs.count)
            for raw in rawIDs {
                guard let id = UUID(uuidString: raw) else { throw Rejection.invalidEvent }
                attachmentIDs.append(id)
            }
            event = .drag(.init(phase: phase, operation: operation, attachmentIDs: attachmentIDs, x: x, y: y))
        default:
            throw Rejection.unknownEventKind
        }
        return .init(documentEpoch: envelope.documentEpoch, sequence: envelope.sequence, direction: direction, echoOfNativeSequence: envelope.echoOfNativeSequence, event: event)
    }

    private struct Envelope: Decodable {
        let documentEpoch: UInt64
        let sequence: UInt64
        let direction: String
        let echoOfNativeSequence: UInt64?
        let event: Event
    }

    private struct Event: Decodable {
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
    }
}

private extension GhostPlaneBridgeMessage.Direction {
    init?(wire: String) {
        switch wire { case "nativeToPlane": self = .nativeToPlane; case "planeToNative": self = .planeToNative; default: return nil }
    }
}
