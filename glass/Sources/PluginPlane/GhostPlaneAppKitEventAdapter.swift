import AppKit
import GlassCore
import UniformTypeIdentifiers

/// Converts native macOS input into the typed Ghost Plane contract. The adapter
/// creates private file leases before emitting paste/drop events, so WebKit can
/// construct genuine File/DataTransfer objects without learning native paths.
@MainActor
public enum GhostPlaneAppKitEventAdapter {
    public static func keyboard(
        from event: NSEvent,
        phase: GhostPlaneBridgeEvent.Keyboard.Phase,
        isComposing: Bool = false
    ) -> GhostPlaneBridgeEvent {
        .keyboard(.init(
            phase: phase,
            key: key(for: event),
            code: code(for: event.keyCode),
            location: location(for: event.keyCode),
            modifiers: modifiers(for: event.modifierFlags),
            isRepeat: event.isARepeat,
            isComposing: isComposing
        ))
    }

    public static func imagePasteEvents(
        from pasteboard: NSPasteboard = .general,
        host: GhostPlaneWebViewHost
    ) -> [GhostPlaneBridgeEvent] {
        leaseImages(from: pasteboard, host: host).map { leased in
            .imagePaste(.init(
                attachmentID: leased.id,
                suggestedName: leased.name,
                mediaType: leased.mediaType
            ))
        }
    }

    static func leaseImages(
        from pasteboard: NSPasteboard,
        host: GhostPlaneWebViewHost
    ) -> [(id: UUID, name: String, mediaType: String)] {
        var leased: [(UUID, String, String)] = []
        let fileObjects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        for object in fileObjects {
            guard let nsURL = object as? NSURL else { continue }
            let url = nsURL as URL
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                  let mediaType = type.preferredMIMEType
            else { continue }
            let id = UUID()
            guard (try? host.leaseTemporaryFile(
                at: url, id: id, suggestedName: url.lastPathComponent, mediaType: mediaType
            )) != nil else { continue }
            leased.append((id, url.lastPathComponent, mediaType))
        }
        if leased.isEmpty, let png = pasteboard.data(forType: .png) {
            let id = UUID()
            let name = "pasted-\(id.uuidString.prefix(8)).png"
            if (try? host.leaseTemporaryData(png, id: id, suggestedName: name, mediaType: "image/png")) != nil {
                leased.append((id, name, "image/png"))
            }
        }
        return leased
    }

    private static func modifiers(for flags: NSEvent.ModifierFlags) -> GhostPlaneBridgeEvent.Keyboard.Modifiers {
        var result: GhostPlaneBridgeEvent.Keyboard.Modifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }

    private static func key(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36, 76: "Enter"
        case 48: "Tab"
        case 49: " "
        case 51: "Backspace"
        case 53: "Escape"
        case 117: "Delete"
        case 123: "ArrowLeft"
        case 124: "ArrowRight"
        case 125: "ArrowDown"
        case 126: "ArrowUp"
        default: event.characters ?? event.charactersIgnoringModifiers ?? "Unidentified"
        }
    }

    private static func code(for keyCode: UInt16) -> String {
        switch keyCode {
        case 36: "Enter"; case 76: "NumpadEnter"; case 48: "Tab"; case 49: "Space"
        case 51: "Backspace"; case 53: "Escape"; case 117: "Delete"
        case 123: "ArrowLeft"; case 124: "ArrowRight"; case 125: "ArrowDown"; case 126: "ArrowUp"
        case 0: "KeyA"; case 11: "KeyB"; case 8: "KeyC"; case 2: "KeyD"; case 14: "KeyE"
        case 3: "KeyF"; case 5: "KeyG"; case 4: "KeyH"; case 34: "KeyI"; case 38: "KeyJ"
        case 40: "KeyK"; case 37: "KeyL"; case 46: "KeyM"; case 45: "KeyN"; case 31: "KeyO"
        case 35: "KeyP"; case 12: "KeyQ"; case 15: "KeyR"; case 1: "KeyS"; case 17: "KeyT"
        case 32: "KeyU"; case 9: "KeyV"; case 13: "KeyW"; case 7: "KeyX"; case 16: "KeyY"; case 6: "KeyZ"
        default: "Unidentified"
        }
    }

    private static func location(for keyCode: UInt16) -> UInt8 {
        let numpad: Set<UInt16> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
        return numpad.contains(keyCode) ? 3 : 0
    }
}

/// Stateful bridge for a single AppKit drag session. File leases are created
/// once at drag-enter and reused for every over/drop event, matching browser
/// DataTransfer identity while avoiding repeated native file reads.
@MainActor
public final class GhostPlaneAppKitDragAdapter {
    private var attachmentIDs: [UUID] = []

    public init() {}

    public func event(
        from dragging: any NSDraggingInfo,
        phase: GhostPlaneBridgeEvent.Drag.Phase,
        host: GhostPlaneWebViewHost
    ) -> GhostPlaneBridgeEvent? {
        if phase == .enter {
            for id in attachmentIDs { host.releaseTemporaryFile(id: id) }
            attachmentIDs = GhostPlaneAppKitEventAdapter
                .leaseImages(from: dragging.draggingPasteboard, host: host)
                .map(\.id)
        }
        guard !attachmentIDs.isEmpty else { return nil }
        let point = dragging.draggingLocation
        let result = GhostPlaneBridgeEvent.drag(.init(
            phase: phase,
            operation: Self.operation(from: dragging.draggingSourceOperationMask),
            attachmentIDs: attachmentIDs,
            x: Double(point.x),
            y: Double(point.y)
        ))
        if phase == .drop || phase == .leave { attachmentIDs = [] }
        return result
    }

    public func cancel(host: GhostPlaneWebViewHost) {
        for id in attachmentIDs { host.releaseTemporaryFile(id: id) }
        attachmentIDs = []
    }

    private static func operation(from mask: NSDragOperation) -> GhostPlaneBridgeEvent.Drag.Operation {
        if mask.contains(.copy) { return .copy }
        if mask.contains(.move) { return .move }
        if mask.contains(.link) { return .link }
        return .none
    }
}
