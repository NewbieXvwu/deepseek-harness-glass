import Foundation

enum HostCompatibility: Equatable, Sendable {
    case verified
    case bestEffort(reason: String)
}
