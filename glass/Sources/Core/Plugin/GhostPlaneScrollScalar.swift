import Foundation

/// Native-authoritative scalar synchronization for the one Ghost Plane document.
///
/// Native conversation content owns real scrolling. The Ghost Plane never reads
/// or writes the native scroll view; it receives one signed `scrollOffset` per
/// source sequence and translates only its internal empty skeleton content. A
/// sequence/epoch fence makes delayed frame callbacks a visual-only loss rather
/// than a functional position rollback.
public struct GhostPlaneScrollScalar: Equatable, Sendable {
    /// A native-supplied document generation. It changes whenever the single
    /// Ghost Plane document is rebuilt, so an old window callback cannot move a
    /// newer document.
    public let documentEpoch: UInt64
    /// Monotonically increasing within `documentEpoch`, assigned by native
    /// scroll observation rather than any plugin.
    public let sequence: UInt64
    /// The exact signed native content offset in points. Signed values preserve
    /// platform elastic overscroll; this is not a plugin-controlled CSS string.
    public let scrollOffset: Double

    public var translationY: Double { -scrollOffset }

    public init(documentEpoch: UInt64, sequence: UInt64, scrollOffset: Double) {
        self.documentEpoch = documentEpoch
        self.sequence = sequence
        self.scrollOffset = scrollOffset
    }

    /// JSON-compatible primitive arguments for a parameterized WebKit call.
    /// The target document creates the CSS transform itself; no caller-supplied
    /// JavaScript source or CSS expression crosses this boundary.
    public var rendererArguments: [String: Double] {
        ["scrollOffset": scrollOffset]
    }
}

/// A deterministic acceptance fence for high-frequency native scroll samples.
/// It intentionally does not sample time, run an animation or infer DOM layout:
/// the UI layer can coalesce display-link writes while this Core value preserves
/// the newest valid source authority and makes every discarded sample explicit.
public struct GhostPlaneScrollSynchronizer: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case applied(GhostPlaneScrollScalar)
        case ignoredStaleEpoch(expected: UInt64, received: UInt64)
        case ignoredStaleSequence(lastApplied: UInt64, received: UInt64)
        case rejectedNonFiniteOffset
    }

    public let documentEpoch: UInt64
    public private(set) var lastApplied: GhostPlaneScrollScalar?

    public init(documentEpoch: UInt64) {
        self.documentEpoch = documentEpoch
    }

    /// Accepts only a finite scalar for the current document and a strictly
    /// newer source sequence. Equality is deliberately stale: applying a second
    /// same-sequence callback after a rebuild/order race could otherwise repaint
    /// a different offset without a new native authority.
    public mutating func receive(sequence: UInt64, scrollOffset: Double, documentEpoch: UInt64) -> Result {
        guard documentEpoch == self.documentEpoch else {
            return .ignoredStaleEpoch(expected: self.documentEpoch, received: documentEpoch)
        }
        guard scrollOffset.isFinite else { return .rejectedNonFiniteOffset }
        if let lastApplied, sequence <= lastApplied.sequence {
            return .ignoredStaleSequence(lastApplied: lastApplied.sequence, received: sequence)
        }
        let scalar = GhostPlaneScrollScalar(
            documentEpoch: documentEpoch,
            sequence: sequence,
            scrollOffset: scrollOffset
        )
        lastApplied = scalar
        return .applied(scalar)
    }
}
