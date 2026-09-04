import Foundation

struct RemoteConnectionGeneration: Hashable, Sendable, Comparable {
    let rawValue: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
