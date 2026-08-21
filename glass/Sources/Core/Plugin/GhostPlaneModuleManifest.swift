import Foundation

/// A fail-closed native admission layer for the official `__DSH_BOOT__` graph.
/// It validates wire data before any WebKit document receives a module URL; it
/// does not execute factories or emulate the JavaScript module system.
struct GhostPlaneModuleManifest: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let url: String
        let rev: String
        let inject: [String]
        let immediately: Bool
        let external: [String]
    }

    let rev: String
    let entries: [Entry]

    enum Admission: Equatable, Sendable {
        case admitted(GhostPlaneModuleManifest)
        case rejected(Reason)
    }

    enum Reason: Equatable, Sendable {
        case malformedWire
        case emptyGraphRevision
        case duplicateEntryID
        case invalidEntryID
        case invalidRevision
        case resourceDenied(GhostPlaneLoopbackPolicy.Denial)
        case resourceIDMismatch
        case invalidClientBundlePath
        case invalidQuery
        case unknownExternalSpecifier
        case dependencyAfterConsumer
    }

    static func admit(
        data: Data,
        policy: GhostPlaneLoopbackPolicy,
        staticModuleSpecifiers: Set<String>
    ) -> Admission {
        guard let manifest = try? JSONDecoder().decode(Self.self, from: data) else {
            return .rejected(.malformedWire)
        }
        guard validRevision(manifest.rev) else { return .rejected(.emptyGraphRevision) }
        let ids = manifest.entries.map(\.id)
        guard Set(ids).count == ids.count else { return .rejected(.duplicateEntryID) }
        let indexByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })

        for (index, entry) in manifest.entries.enumerated() {
            guard validPluginID(entry.id) else { return .rejected(.invalidEntryID) }
            guard validRevision(entry.rev) else { return .rejected(.invalidRevision) }
            guard let url = URL(string: entry.url) else { return .rejected(.malformedWire) }
            switch policy.decision(for: url) {
            case .deny(let reason):
                return .rejected(.resourceDenied(reason))
            case .allowSkeletonDocument:
                return .rejected(.invalidClientBundlePath)
            case .allowPluginResource(let pluginID):
                guard pluginID == entry.id else { return .rejected(.resourceIDMismatch) }
            }
            guard exactClientBundleURL(url, pluginID: entry.id, revision: entry.rev) else {
                return .rejected(.invalidClientBundlePath)
            }
            guard validSpecifierArray(entry.inject), validSpecifierArray(entry.external) else {
                return .rejected(.unknownExternalSpecifier)
            }
            for requested in entry.external {
                let dependencyID = stripClientSuffix(requested)
                if staticModuleSpecifiers.contains(requested) || staticModuleSpecifiers.contains(dependencyID) { continue }
                guard let dependencyIndex = indexByID[dependencyID] else {
                    return .rejected(.unknownExternalSpecifier)
                }
                guard dependencyIndex < index else { return .rejected(.dependencyAfterConsumer) }
            }
        }
        return .admitted(manifest)
    }

    private static func exactClientBundleURL(_ url: URL, pluginID: String, revision: String) -> Bool {
        guard url.path == "/plugins/\(pluginID)/client.js",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        let query = components.queryItems ?? []
        return query.count == 1 && query[0].name == "rev" && query[0].value == revision
    }

    private static func validRevision(_ revision: String) -> Bool {
        guard !revision.isEmpty, revision.count <= 256 else { return false }
        return revision.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 95, 48...57, 65...90, 97...122: true
            default: false
            }
        }
    }

    private static func validPluginID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 95, 48...57, 65...90, 97...122: true
            default: false
            }
        }
    }

    private static func validSpecifierArray(_ values: [String]) -> Bool {
        values.allSatisfy { !$0.isEmpty && $0.count <= 256 && !$0.contains("\\") && !$0.contains("%") }
    }

    private static func stripClientSuffix(_ specifier: String) -> String {
        specifier.hasSuffix("/client") ? String(specifier.dropLast("/client".count)) : specifier
    }
}
