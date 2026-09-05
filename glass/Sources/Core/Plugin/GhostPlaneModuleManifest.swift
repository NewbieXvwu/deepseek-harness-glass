import Foundation

/// Fail-closed admission for the rc.1 `window.__DSH_BOOT__` graph. The wire
/// carries single-resource HMR URLs plus content-addressed initial-load batches.
public struct GhostPlaneModuleManifest: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let url: String
        public let rev: String
        public let inject: [String]
        public let immediately: Bool
        public let external: [String]
    }

    public struct Batch: Codable, Equatable, Sendable {
        public enum Phase: String, Codable, Sendable { case bootstrap, application }
        public let phase: Phase
        public let url: String
        public let rev: String
        public let entries: [String]
    }

    public let rev: String
    public let entries: [Entry]
    public let batches: [Batch]

    public enum Admission: Equatable, Sendable { case admitted(GhostPlaneModuleManifest), rejected(Reason) }
    public enum Reason: Equatable, Sendable {
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
        case duplicateBatchURL
        case emptyBatch
        case unknownBatchEntry
        case duplicateBatchMembership
        case missingBatchMembership
    }

    public static func admit(data: Data, policy: GhostPlaneLoopbackPolicy, staticModuleSpecifiers: Set<String>) -> Admission {
        guard let manifest = try? JSONDecoder().decode(Self.self, from: data) else { return .rejected(.malformedWire) }
        guard validRevision(manifest.rev) else { return .rejected(.emptyGraphRevision) }
        let ids = manifest.entries.map(\.id)
        guard Set(ids).count == ids.count else { return .rejected(.duplicateEntryID) }
        let indexByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })

        for (index, entry) in manifest.entries.enumerated() {
            guard GhostPlaneLoopbackPolicy.isValidPluginID(entry.id) else { return .rejected(.invalidEntryID) }
            guard validRevision(entry.rev) else { return .rejected(.invalidRevision) }
            guard let url = URL(string: entry.url) else { return .rejected(.malformedWire) }
            switch policy.decision(for: url) {
            case .deny(let reason): return .rejected(.resourceDenied(reason))
            case .allowPluginCombo(let pluginIDs, let sourceMap):
                guard pluginIDs == [entry.id], !sourceMap else { return .rejected(.resourceIDMismatch) }
            default: return .rejected(.invalidClientBundlePath)
            }
            guard exactComboURL(url, ids: [entry.id], revision: entry.rev, sourceMap: false) else { return .rejected(.invalidClientBundlePath) }
            guard validSpecifierArray(entry.inject), validSpecifierArray(entry.external) else { return .rejected(.unknownExternalSpecifier) }
            for requested in entry.external {
                let dependencyID = stripClientSuffix(requested)
                if staticModuleSpecifiers.contains(requested) || staticModuleSpecifiers.contains(dependencyID) { continue }
                guard let dependencyIndex = indexByID[dependencyID] else { return .rejected(.unknownExternalSpecifier) }
                guard dependencyIndex < index else { return .rejected(.dependencyAfterConsumer) }
            }
        }

        var membership: [String: String] = [:]
        var batchURLs: Set<String> = []
        for batch in manifest.batches {
            guard validRevision(batch.rev) else { return .rejected(.invalidRevision) }
            guard !batch.entries.isEmpty else { return .rejected(.emptyBatch) }
            guard batchURLs.insert(batch.url).inserted else { return .rejected(.duplicateBatchURL) }
            guard Set(batch.entries).count == batch.entries.count else { return .rejected(.duplicateBatchMembership) }
            for id in batch.entries {
                guard indexByID[id] != nil else { return .rejected(.unknownBatchEntry) }
                guard membership[id] == nil else { return .rejected(.duplicateBatchMembership) }
                membership[id] = batch.url
            }
            guard let url = URL(string: batch.url) else { return .rejected(.malformedWire) }
            switch policy.decision(for: url) {
            case .allowPluginCombo(let ids, let sourceMap) where ids == batch.entries && !sourceMap: break
            case .deny(let reason): return .rejected(.resourceDenied(reason))
            default: return .rejected(.invalidClientBundlePath)
            }
            guard exactComboURL(url, ids: batch.entries, revision: batch.rev, sourceMap: false) else { return .rejected(.invalidClientBundlePath) }
        }
        guard membership.count == manifest.entries.count else { return .rejected(.missingBatchMembership) }
        return .admitted(manifest)
    }

    private static func exactComboURL(_ url: URL, ids: [String], revision: String, sourceMap: Bool) -> Bool {
        guard url.path == "/plugins" || url.path == "/plugins/", let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery else { return false }
        let resourceSuffix = sourceMap ? "/client.js.map" : "/client.js"
        return query == "?" + ids.map { $0 + resourceSuffix }.joined(separator: ",") + "&rev=" + revision
    }
    private static func validRevision(_ revision: String) -> Bool {
        !revision.isEmpty && revision.count <= 256 && revision.unicodeScalars.allSatisfy { scalar in
            switch scalar.value { case 45, 46, 95, 48...57, 65...90, 97...122: true; default: false }
        }
    }
    private static func validSpecifierArray(_ values: [String]) -> Bool { values.allSatisfy { !$0.isEmpty && $0.count <= 256 && !$0.contains("\\") && !$0.contains("%") } }
    private static func stripClientSuffix(_ specifier: String) -> String { specifier.hasSuffix("/client") ? String(specifier.dropLast("/client".count)) : specifier }
}
