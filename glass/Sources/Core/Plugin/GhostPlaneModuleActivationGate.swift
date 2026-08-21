import Foundation

/// Native ledger between an admitted boot graph and any future WebKit factory
/// execution. It identifies bundle arrival by the exact graph `(pluginID, rev)`
/// pair and yields only an opaque activation permit; it never stores a factory,
/// JavaScript source, exports, or injected service object.
public struct GhostPlaneModuleActivationGate: Equatable, Sendable {
    public struct ActivationPermit: Equatable, Sendable {
        public let pluginID: String
        public let revision: String
        public let graphRevision: String
    }

    public enum Arrival: Equatable, Sendable {
        case admitted
        case rejected(Rejection)
    }

    public enum Activation: Equatable, Sendable {
        case permitted(ActivationPermit)
        case rejected(Rejection)
    }

    public enum Rejection: Equatable, Sendable {
        case unknownBundle
        case revisionMismatch
        case duplicateArrival
        case bundleNotArrived
        case dependencyNotArrived(String)
        case alreadyActivated
    }

    private let manifest: GhostPlaneModuleManifest
    private let staticModuleSpecifiers: Set<String>
    private var arrived: Set<String> = []
    private var activated: Set<String> = []

    public init(manifest: GhostPlaneModuleManifest, staticModuleSpecifiers: Set<String>) {
        self.manifest = manifest
        self.staticModuleSpecifiers = staticModuleSpecifiers
    }

    /// Records a browser bundle arrival after the host has independently tied
    /// the script response to an admitted graph row. An id never gains access
    /// through a matching revision alone.
    public mutating func admitArrival(pluginID: String, revision: String) -> Arrival {
        guard let entry = manifest.entries.first(where: { $0.id == pluginID }) else {
            return .rejected(.unknownBundle)
        }
        guard entry.rev == revision else { return .rejected(.revisionMismatch) }
        guard !arrived.contains(pluginID) else { return .rejected(.duplicateArrival) }
        arrived.insert(pluginID)
        return .admitted
    }

    /// Issues the one-shot opaque permit needed by the later typed injector.
    /// Non-static externals must already have reached the same native ledger;
    /// factory execution therefore cannot import an unobserved table word.
    public mutating func permitActivation(pluginID: String) -> Activation {
        guard let index = manifest.entries.firstIndex(where: { $0.id == pluginID }) else {
            return .rejected(.unknownBundle)
        }
        guard arrived.contains(pluginID) else { return .rejected(.bundleNotArrived) }
        guard !activated.contains(pluginID) else { return .rejected(.alreadyActivated) }
        let entry = manifest.entries[index]
        for specifier in entry.external {
            let dependencyID = Self.stripClientSuffix(specifier)
            if staticModuleSpecifiers.contains(specifier) || staticModuleSpecifiers.contains(dependencyID) { continue }
            guard arrived.contains(dependencyID) else { return .rejected(.dependencyNotArrived(dependencyID)) }
        }
        activated.insert(pluginID)
        return .permitted(.init(pluginID: entry.id, revision: entry.rev, graphRevision: manifest.rev))
    }

    private static func stripClientSuffix(_ specifier: String) -> String {
        specifier.hasSuffix("/client") ? String(specifier.dropLast("/client".count)) : specifier
    }
}
