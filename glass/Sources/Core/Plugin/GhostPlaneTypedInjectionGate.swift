import Foundation

/// Converts a graph-bound activation permit into a declarative service-name
/// grant. Actual service objects remain native-owned and are supplied only by a
/// later audited bridge; this Core gate never serializes an object, callback,
/// selector, or JavaScript capability into the plugin document.
public struct GhostPlaneTypedInjectionGate: Equatable, Sendable {
    public enum Service: String, CaseIterable, Sendable {
        case modules
        case slots
        case locale
        case session
        case attachmentAdmission = "attachment-admission"
        case permissionBroker = "permission-broker"
    }

    public struct Grant: Equatable, Sendable {
        public let pluginID: String
        public let revision: String
        public let graphRevision: String
        public let services: [Service]
    }

    public enum Decision: Equatable, Sendable {
        case granted(Grant)
        case rejected(Rejection)
    }

    public enum Rejection: Equatable, Sendable {
        case unknownPlugin
        case revisionMismatch
        case graphRevisionMismatch
        case unknownService(String)
        case unavailableService(Service)
    }

    private let manifest: GhostPlaneModuleManifest
    private let availableServices: Set<Service>

    public init(manifest: GhostPlaneModuleManifest, availableServices: Set<Service>) {
        self.manifest = manifest
        self.availableServices = availableServices
    }

    public func grant(for permit: GhostPlaneModuleActivationGate.ActivationPermit) -> Decision {
        guard permit.graphRevision == manifest.rev else { return .rejected(.graphRevisionMismatch) }
        guard let entry = manifest.entries.first(where: { $0.id == permit.pluginID }) else {
            return .rejected(.unknownPlugin)
        }
        guard entry.rev == permit.revision else { return .rejected(.revisionMismatch) }
        var services: [Service] = []
        for token in entry.inject {
            guard let service = Service(rawValue: token) else { return .rejected(.unknownService(token)) }
            guard availableServices.contains(service) else { return .rejected(.unavailableService(service)) }
            if !services.contains(service) { services.append(service) }
        }
        return .granted(.init(pluginID: entry.id, revision: entry.rev, graphRevision: manifest.rev, services: services))
    }
}
