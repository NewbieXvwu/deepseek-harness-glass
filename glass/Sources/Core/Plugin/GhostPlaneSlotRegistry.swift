import Foundation

/// Registry for the fixed Ghost Plane skeleton slots. Unlike the upstream
/// React/Cordis registry, this Core layer never accepts a component/factory;
/// a later reviewed renderer may consume only its typed placement plan.
public struct GhostPlaneSlotRegistry: Equatable, Sendable {
    public enum Slot: String, CaseIterable, Sendable {
        case session = "conversation.session"
        case sessionHeader = "conversation.session.header"
        case chatNode = "conversation.chat.node"
        case chatTurnTail = "conversation.chat.turnTail"
        case detailsTool = "conversation.details.tool"
        case composer = "conversation.composer"
        case toolview = "tool.call.toolview"
    }
    public struct Registration: Equatable, Sendable, Identifiable {
        public let pluginID: String
        public let registrationID: String
        public let slot: Slot
        public let order: Int
        public var id: String { "\(pluginID):\(slot.rawValue):\(registrationID)" }
        public init(pluginID: String, id: String, slot: Slot, order: Int = 0) {
            self.pluginID = pluginID; self.registrationID = id; self.slot = slot; self.order = order
        }
    }
    public enum Rejection: Error, Equatable, Sendable { case invalidPluginID, invalidRegistrationID, duplicateRegistration }
    private var entries: [String: Registration] = [:]
    public init() {}
    public mutating func register(pluginID: String, id: String, slot: Slot, order: Int = 0) throws -> Registration {
        guard Self.valid(pluginID) else { throw Rejection.invalidPluginID }
        guard Self.valid(id) else { throw Rejection.invalidRegistrationID }
        let registration = Registration(pluginID: pluginID, id: id, slot: slot, order: order)
        guard entries[registration.id] == nil else { throw Rejection.duplicateRegistration }
        entries[registration.id] = registration
        return registration
    }
    public mutating func unregister(_ registration: Registration) { entries.removeValue(forKey: registration.id) }
    public func placements(in slot: Slot) -> [Registration] { entries.values.filter { $0.slot == slot }.sorted { ($0.order, $0.id) < ($1.order, $1.id) } }
    private static func valid(_ value: String) -> Bool { !value.isEmpty && value.count <= 128 && value.unicodeScalars.allSatisfy { $0.value == 45 || $0.value == 46 || $0.value == 95 || (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) } }
}
