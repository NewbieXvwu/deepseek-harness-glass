import Foundation

/// Typed, non-executable event data accepted by the Ghost Plane boundary.
/// Native/AppKit and WebKit adapters own platform object construction; Core only
/// retains the complete serializable semantics and sequence authority.
public enum GhostPlaneBridgeEvent: Equatable, Sendable {
    public struct Keyboard: Equatable, Sendable {
        public struct Modifiers: OptionSet, Equatable, Sendable {
            public let rawValue: UInt8
            public init(rawValue: UInt8) { self.rawValue = rawValue }
            public static let shift = Self(rawValue: 1 << 0)
            public static let control = Self(rawValue: 1 << 1)
            public static let option = Self(rawValue: 1 << 2)
            public static let command = Self(rawValue: 1 << 3)
            public static let capsLock = Self(rawValue: 1 << 4)
            public static let function = Self(rawValue: 1 << 5)
        }

        public enum Phase: String, Equatable, Sendable { case down, up }
        public let phase: Phase
        public let key: String
        public let code: String
        public let location: UInt8
        public let modifiers: Modifiers
        public let isRepeat: Bool
        public let isComposing: Bool

        public init(
            phase: Phase,
            key: String,
            code: String,
            location: UInt8,
            modifiers: Modifiers,
            isRepeat: Bool,
            isComposing: Bool
        ) {
            self.phase = phase
            self.key = key
            self.code = code
            self.location = location
            self.modifiers = modifiers
            self.isRepeat = isRepeat
            self.isComposing = isComposing
        }
    }

    /// Image bytes never travel through a plugin message. The native adapter
    /// creates a Host-private temporary file and hands its opaque attachment ID
    /// to the existing `NativeImageAttachmentAdmission` path.
    public struct ImagePaste: Equatable, Sendable {
        public let attachmentID: UUID
        public let suggestedName: String
        public let mediaType: String

        public init(attachmentID: UUID, suggestedName: String, mediaType: String) {
            self.attachmentID = attachmentID
            self.suggestedName = suggestedName
            self.mediaType = mediaType
        }
    }

    /// DOM selection is projected using skeleton-owned node IDs/offsets. No
    /// HTML, Range object, selector or copied text crosses the bridge.
    public struct Selection: Equatable, Sendable {
        public let anchorID: String
        public let anchorOffset: UInt32
        public let focusID: String
        public let focusOffset: UInt32
        public let isCollapsed: Bool

        public init(
            anchorID: String,
            anchorOffset: UInt32,
            focusID: String,
            focusOffset: UInt32,
            isCollapsed: Bool
        ) {
            self.anchorID = anchorID
            self.anchorOffset = anchorOffset
            self.focusID = focusID
            self.focusOffset = focusOffset
            self.isCollapsed = isCollapsed
        }
    }

    public struct Drag: Equatable, Sendable {
        public enum Phase: String, Equatable, Sendable { case enter, over, leave, drop }
        public enum Operation: String, Equatable, Sendable { case copy, move, link, none }
        public let phase: Phase
        public let operation: Operation
        public let attachmentIDs: [UUID]
        public let x: Double
        public let y: Double

        public init(phase: Phase, operation: Operation, attachmentIDs: [UUID], x: Double, y: Double) {
            self.phase = phase
            self.operation = operation
            self.attachmentIDs = attachmentIDs
            self.x = x
            self.y = y
        }
    }

    case keyboard(Keyboard)
    case imagePaste(ImagePaste)
    case selection(Selection)
    case drag(Drag)
}

public struct GhostPlaneBridgeMessage: Equatable, Sendable {
    public enum Direction: Equatable, Sendable { case nativeToPlane, planeToNative }

    public let documentEpoch: UInt64
    public let sequence: UInt64
    public let direction: Direction
    /// Native generated messages carry no echo. A plane observation caused by a
    /// known native injection must carry that injected sequence so Core can
    /// suppress it rather than reflexively writing it back into native state.
    public let echoOfNativeSequence: UInt64?
    public let event: GhostPlaneBridgeEvent

    public init(
        documentEpoch: UInt64,
        sequence: UInt64,
        direction: Direction,
        echoOfNativeSequence: UInt64? = nil,
        event: GhostPlaneBridgeEvent
    ) {
        self.documentEpoch = documentEpoch
        self.sequence = sequence
        self.direction = direction
        self.echoOfNativeSequence = echoOfNativeSequence
        self.event = event
    }
}

/// Per-document authority/fence for native ↔ WebKit event movement. It makes
/// direction explicit and stores only a bounded identity window, so high-rate
/// input cannot make loop suppression unbounded.
public struct GhostPlaneEventBridgeFence: Equatable, Sendable {
    public enum PlaneReceipt: Equatable, Sendable {
        case deliver(GhostPlaneBridgeEvent)
        case suppressNativeEcho
        case rejectedWrongEpoch(expected: UInt64, received: UInt64)
        case rejectedWrongDirection
        case rejectedStaleSequence(lastReceived: UInt64, received: UInt64)
        case rejectedUnknownEcho
        case rejectedInvalidEvent
    }

    public let documentEpoch: UInt64
    public let echoWindow: Int
    private var nextNativeSequence: UInt64 = 0
    private var lastPlaneSequence: UInt64?
    private var knownNativeSequences: [UInt64] = []

    public init(documentEpoch: UInt64, echoWindow: Int = 256) {
        self.documentEpoch = documentEpoch
        self.echoWindow = max(1, echoWindow)
    }

    /// Issues a source-native event for the current document. Sequence overflow
    /// wraps deliberately; a fresh document epoch accompanies a real lifecycle
    /// reset, and the bounded echo identity list is cleared with this value.
    public mutating func emitNative(_ event: GhostPlaneBridgeEvent) -> GhostPlaneBridgeMessage? {
        guard Self.valid(event) else { return nil }
        nextNativeSequence &+= 1
        knownNativeSequences.append(nextNativeSequence)
        if knownNativeSequences.count > echoWindow { knownNativeSequences.removeFirst() }
        return .init(
            documentEpoch: documentEpoch,
            sequence: nextNativeSequence,
            direction: .nativeToPlane,
            event: event
        )
    }

    /// Admits a message observed from the page. Only the page-to-native
    /// direction and monotonic plane sequence can reach native state. A known
    /// native echo is consumed; an unknown echo is rejected rather than treated
    /// as a new user interaction.
    public mutating func receivePlane(_ message: GhostPlaneBridgeMessage) -> PlaneReceipt {
        guard message.documentEpoch == documentEpoch else {
            return .rejectedWrongEpoch(expected: documentEpoch, received: message.documentEpoch)
        }
        guard message.direction == .planeToNative else { return .rejectedWrongDirection }
        if let lastPlaneSequence, message.sequence <= lastPlaneSequence {
            return .rejectedStaleSequence(lastReceived: lastPlaneSequence, received: message.sequence)
        }
        guard Self.valid(message.event) else { return .rejectedInvalidEvent }
        lastPlaneSequence = message.sequence
        if let echo = message.echoOfNativeSequence {
            return knownNativeSequences.contains(echo) ? .suppressNativeEcho : .rejectedUnknownEcho
        }
        return .deliver(message.event)
    }

    private static func valid(_ event: GhostPlaneBridgeEvent) -> Bool {
        switch event {
        case .keyboard(let key):
            return key.key.count <= 128
                && key.code.count <= 128
                && key.location <= 3
                && key.modifiers.rawValue & ~UInt8(0b00_111111) == 0
        case .imagePaste(let image):
            return !image.suggestedName.isEmpty && image.suggestedName.count <= 255
                && !image.mediaType.isEmpty && image.mediaType.count <= 128
        case .selection(let selection):
            return validSkeletonID(selection.anchorID) && validSkeletonID(selection.focusID)
                && (!selection.isCollapsed || (selection.anchorID == selection.focusID && selection.anchorOffset == selection.focusOffset))
        case .drag(let drag):
            return drag.attachmentIDs.count <= 64 && Set(drag.attachmentIDs).count == drag.attachmentIDs.count
                && drag.x.isFinite && drag.y.isFinite
        }
    }

    private static func validSkeletonID(_ value: String) -> Bool {
        guard value.hasPrefix("ghost-"), !value.isEmpty, value.count <= 256 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 58, 95, 48...57, 65...90, 97...122: true
            default: false
            }
        }
    }
}
