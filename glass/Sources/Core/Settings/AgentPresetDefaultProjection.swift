import Foundation

/// Persisted default agent preset from RC8 `ui-agent-preset/settings-store.ts`.
/// The Host roster remains the source for valid choices; this state only
/// projects the official settings namespace and never creates an option list.
struct CoreAgentPresetDefaultState: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case unavailable
        case malformed
        case ready
    }

    let status: Status
    let writable: Bool
    let current: String?
    let revision: Int?

    func mutation(selecting presetID: String) -> SettingsPathOperationDTO? {
        guard status == .ready, writable, !presetID.isEmpty else { return nil }
        return .set(path: AgentPresetDefaultProjection.path, value: .string(presetID))
    }
}

/// Host-authoritative projection of the one default field that governs sessions
/// created without an explicit staged agent preset.
enum AgentPresetDefaultProjection {
    static let namespace = "agent-presets"
    static let path = ["default"]

    static func state(namespaces: [SettingsNamespaceDTO], writable: Bool) -> CoreAgentPresetDefaultState {
        guard let namespace = namespaces.first(where: { $0.ns == Self.namespace }) else {
            return .init(status: .unavailable, writable: false, current: nil, revision: nil)
        }
        guard let current = namespace.value.objectValue?[path[0]]?.stringValue, !current.isEmpty else {
            return .init(status: .malformed, writable: false, current: nil, revision: namespace.revision)
        }
        return .init(status: .ready, writable: writable, current: current, revision: namespace.revision)
    }
}
