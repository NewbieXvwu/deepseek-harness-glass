import Foundation

/// Native-owned remembered decision for a plugin capability. A plugin can only
/// request; it cannot seed, edit or enumerate decisions for another plugin.
public struct GhostPlanePermissionBroker: Equatable, Sendable {
    public enum Capability: String, CaseIterable, Equatable, Sendable {
        case notifications
        case clipboardRead
        case clipboardWrite
        case download
        case openFilePicker
        case externalNavigation
    }

    public enum Decision: Equatable, Sendable { case needsNativePrompt, granted, denied, invalidPlugin }
    public enum Resolution: Equatable, Sendable { case grant, deny }

    public struct Record: Equatable, Sendable, Identifiable {
        public let pluginID: String
        public let capability: Capability
        public let resolution: Resolution
        public var id: String { "\(pluginID):\(capability.rawValue)" }
    }

    private var decisions: [Key: Resolution] = [:]

    public init() {}

    public func decision(for pluginID: String, capability: Capability) -> Decision {
        guard Self.validPluginID(pluginID) else { return .invalidPlugin }
        switch decisions[.init(pluginID: pluginID, capability: capability)] {
        case .grant: return .granted
        case .deny: return .denied
        case nil: return .needsNativePrompt
        }
    }

    /// Called exclusively by the native confirmation UI after a first request.
    /// It will not create a record unless the capability is currently undecided.
    @discardableResult
    public mutating func resolveFirstRequest(
        pluginID: String,
        capability: Capability,
        resolution: Resolution
    ) -> Decision {
        guard Self.validPluginID(pluginID) else { return .invalidPlugin }
        let key = Key(pluginID: pluginID, capability: capability)
        guard decisions[key] == nil else { return decision(for: pluginID, capability: capability) }
        decisions[key] = resolution
        return decision(for: pluginID, capability: capability)
    }

    /// Native Settings can revoke a remembered decision. It cannot fabricate a
    /// grant: the next plugin request must again invoke the first-call prompt.
    public mutating func revoke(pluginID: String, capability: Capability) -> Bool {
        guard Self.validPluginID(pluginID) else { return false }
        return decisions.removeValue(forKey: .init(pluginID: pluginID, capability: capability)) != nil
    }

    /// For a native Settings audit surface. The caller can filter by displayed
    /// plugin inventory; this value has no mutable/preauthorization operation.
    public var records: [Record] {
        decisions.map { key, resolution in
            .init(pluginID: key.pluginID, capability: key.capability, resolution: resolution)
        }.sorted { $0.id < $1.id }
    }

    private struct Key: Hashable, Sendable {
        let pluginID: String
        let capability: Capability
    }

    private static func validPluginID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 95, 48...57, 65...90, 97...122: true
            default: false
            }
        }
    }
}
