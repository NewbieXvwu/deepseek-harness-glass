import Foundation

/// Reviewed rc.1 SlotMap admission for the shared Ghost Plane.
///
/// The upstream slot declaration remains the authority for name/kind/scope and
/// source provenance. Glass adds only an explicit placement policy: green slots
/// may mount in the shared transparent plane, red slots remain native-owned, and
/// managed slots require the separately registered full-view container.
public struct GhostPlaneSlotRegistry: Equatable, Sendable {
    public struct Slot: Equatable, Sendable, Identifiable {
        public enum Zone: String, Equatable, Sendable { case red, green, managed }
        public enum Anchor: String, Equatable, Sendable {
            case conversation, header, hero, chat, composer, details
            case managedView = "managed-view"
        }

        public let name: String
        public let kind: String
        public let scope: String
        public let sourcePath: String
        public let anchor: Anchor
        public let zone: Zone
        public var id: String { name }
    }

    public struct Registration: Equatable, Sendable, Identifiable {
        public let pluginID: String
        public let registrationID: String
        public let slot: Slot
        public let order: Int
        public var id: String { "\(pluginID):\(slot.name):\(registrationID)" }
    }

    public enum Rejection: Error, Equatable, Sendable {
        case invalidPluginID
        case invalidRegistrationID
        case unknownSlot
        case redZone
        case managedContainerRequired
        case duplicateRegistration
        case contractUnavailable
    }

    public let slots: [Slot]
    private let slotsByName: [String: Slot]
    private var entries: [String: Registration] = [:]

    public init() throws {
        let fixture: OfficialGhostPlaneContract.Fixture
        do { fixture = try OfficialGhostPlaneContract.load() }
        catch { throw Rejection.contractUnavailable }

        let decoded = try fixture.slots.map { slot -> Slot in
            guard let zone = Slot.Zone(rawValue: slot.zone),
                  let anchor = Slot.Anchor(rawValue: slot.anchor)
            else { throw Rejection.contractUnavailable }
            return Slot(
                name: slot.name,
                kind: slot.kind,
                scope: slot.scope,
                sourcePath: slot.sourcePath,
                anchor: anchor,
                zone: zone
            )
        }
        guard Set(decoded.map(\.name)).count == decoded.count else {
            throw Rejection.contractUnavailable
        }
        slots = decoded.sorted { $0.name < $1.name }
        slotsByName = Dictionary(uniqueKeysWithValues: slots.map { ($0.name, $0) })
    }

    public var greenSlots: [Slot] { slots.filter { $0.zone == .green } }
    public var redSlots: [Slot] { slots.filter { $0.zone == .red } }
    public var managedSlots: [Slot] { slots.filter { $0.zone == .managed } }

    @discardableResult
    public mutating func register(
        pluginID: String,
        id: String,
        slotName: String,
        order: Int = 0
    ) throws -> Registration {
        guard Self.valid(pluginID) else { throw Rejection.invalidPluginID }
        guard Self.valid(id) else { throw Rejection.invalidRegistrationID }
        guard let slot = slotsByName[slotName] else { throw Rejection.unknownSlot }
        switch slot.zone {
        case .red: throw Rejection.redZone
        case .managed: throw Rejection.managedContainerRequired
        case .green: break
        }
        let registration = Registration(pluginID: pluginID, registrationID: id, slot: slot, order: order)
        guard entries[registration.id] == nil else { throw Rejection.duplicateRegistration }
        entries[registration.id] = registration
        return registration
    }

    public mutating func unregister(_ registration: Registration) {
        entries.removeValue(forKey: registration.id)
    }

    public func placements(in slotName: String) -> [Registration] {
        entries.values
            .filter { $0.slot.name == slotName }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    private static func valid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128, !value.contains("..") else { return false }
        return value.unicodeScalars.allSatisfy {
            $0.value == 45 || $0.value == 46 || $0.value == 47 || $0.value == 64 || $0.value == 95 ||
            (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value)
        }
    }
}
