import Foundation

/// A source-attributed, bounded subset of official `webServer.tapIndex` replay.
///
/// Upstream tap callbacks are arbitrary JavaScript functions over raw index HTML.
/// They cannot cross into the native Ghost Plane as code: evaluating raw callback
/// source would turn the loopback document into a second plugin execution path.
/// This value instead carries the replayable compatibility subset after the Host
/// has translated it into structural mutations. The WebKit target may apply the
/// returned values only after a manifest has passed `GhostPlaneModuleManifest`
/// admission and only to the native-authoritative empty skeleton.
public struct GhostPlaneTapIndexReplay: Equatable, Sendable {
    public struct Source: Equatable, Sendable {
        public let pluginID: String
        public let revision: String

        public init(pluginID: String, revision: String) {
            self.pluginID = pluginID
            self.revision = revision
        }
    }

    public enum Target: String, CaseIterable, Equatable, Hashable, Sendable {
        case planeRoot = "ghost-plane-root"
        case sessionHeader = "ghost-session-header"
        case conversationScroll = "ghost-conversation-scroll"
        case chatFlow = "ghost-chat-flow"
        case composerSeat = "ghost-composer-seat"
        case turnTail = "ghost-turn-tail"
        case detailsTool = "ghost-details-tool"
    }

    /// The controlled dialect deliberately contains no HTML string, selector,
    /// event handler, URL or executable source. CSS properties are custom token
    /// names only, and classes/attributes remain under native-owned prefixes.
    public enum Mutation: Equatable, Hashable, Sendable {
        case setCustomProperty(name: String, value: String)
        case setDataAttribute(name: String, value: String)
        case addCompatibilityClass(String)
    }

    public struct Record: Equatable, Sendable {
        public let source: Source
        public let target: Target
        public let mutation: Mutation

        public init(source: Source, target: Target, mutation: Mutation) {
            self.source = source
            self.target = target
            self.mutation = mutation
        }
    }

    public enum Rejection: Equatable, Sendable {
        case unknownPlugin
        case revisionMismatch
        case duplicateMutation
        case unsafeCustomPropertyName
        case unsafeCustomPropertyValue
        case unsafeDataAttributeName
        case unsafeDataAttributeValue
        case unsafeCompatibilityClass
    }

    public enum Admission: Equatable, Sendable {
        case admitted(GhostPlaneTapIndexReplay)
        case rejected(Rejection)
    }

    public let graphRevision: String
    public let records: [Record]

    private init(graphRevision: String, records: [Record]) {
        self.graphRevision = graphRevision
        self.records = records
    }

    /// Admits a deterministic replay in host collection order. Identity is bound
    /// to the admitted graph: a plugin cannot replay a tap for another plugin or
    /// a stale bundle revision, and a conflicting write is rejected rather than
    /// resolved by incidental ordering.
    public static func admit(
        records: [Record],
        for manifest: GhostPlaneModuleManifest
    ) -> Admission {
        let revisions = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.id, $0.rev) })
        var claimed = Set<Claim>()

        for record in records {
            guard let revision = revisions[record.source.pluginID] else {
                return .rejected(.unknownPlugin)
            }
            guard revision == record.source.revision else {
                return .rejected(.revisionMismatch)
            }
            guard valid(record.mutation) else {
                return .rejected(rejection(for: record.mutation))
            }
            let claim = Claim(target: record.target, mutation: record.mutation)
            guard claimed.insert(claim).inserted else {
                return .rejected(.duplicateMutation)
            }
        }

        return .admitted(Self(graphRevision: manifest.rev, records: records))
    }

    /// A JSON-compatible renderer payload. It contains only admitted primitive
    /// values, enabling the WebKit target to pass it as `callAsyncJavaScript`
    /// arguments rather than interpolating plugin-controlled text into script.
    public func rendererPayload() -> [[String: String]] {
        records.map { record in
            var payload = [
                "pluginID": record.source.pluginID,
                "revision": record.source.revision,
                "targetID": record.target.rawValue,
            ]
            switch record.mutation {
            case .setCustomProperty(let name, let value):
                payload["kind"] = "customProperty"
                payload["name"] = name
                payload["value"] = value
            case .setDataAttribute(let name, let value):
                payload["kind"] = "dataAttribute"
                payload["name"] = name
                payload["value"] = value
            case .addCompatibilityClass(let name):
                payload["kind"] = "compatibilityClass"
                payload["name"] = name
            }
            return payload
        }
    }

    private struct Claim: Hashable {
        let target: Target
        let mutation: Mutation
    }

    private static func valid(_ mutation: Mutation) -> Bool {
        switch mutation {
        case .setCustomProperty(let name, let value):
            return validCustomPropertyName(name) && validCustomPropertyValue(value)
        case .setDataAttribute(let name, let value):
            return validDataAttributeName(name) && validDataAttributeValue(value)
        case .addCompatibilityClass(let name):
            return validCompatibilityClass(name)
        }
    }

    private static func rejection(for mutation: Mutation) -> Rejection {
        switch mutation {
        case .setCustomProperty(let name, _):
            return validCustomPropertyName(name) ? .unsafeCustomPropertyValue : .unsafeCustomPropertyName
        case .setDataAttribute(let name, _):
            return validDataAttributeName(name) ? .unsafeDataAttributeValue : .unsafeDataAttributeName
        case .addCompatibilityClass:
            return .unsafeCompatibilityClass
        }
    }

    private static func validCustomPropertyName(_ value: String) -> Bool {
        guard value.hasPrefix("--dsh-") || value.hasPrefix("--ghost-") else { return false }
        return validLowercaseToken(value.dropFirst(2), maximum: 96)
    }

    private static func validCustomPropertyValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 256 else { return false }
        // Non-localized ASCII containment: locale-aware matching ("İ") would
        // make this depend on the user's region. The character whitelist below
        // remains the primary gate; these are a final block.
        guard value.range(of: "url", options: .caseInsensitive) == nil,
              value.range(of: "expression", options: .caseInsensitive) == nil,
              value.range(of: "@import", options: .caseInsensitive) == nil
        else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 32, 35, 37, 40, 41, 43, 44, 45, 46, 47, 48...57, 65...90, 97...122:
                true
            default:
                false
            }
        }
    }

    private static func validDataAttributeName(_ value: String) -> Bool {
        guard value.hasPrefix("data-ghost-") else { return false }
        return validLowercaseToken(value.dropFirst("data-".count), maximum: 96)
    }

    private static func validDataAttributeValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 58, 95, 48...57, 65...90, 97...122:
                true
            default:
                false
            }
        }
    }

    private static func validCompatibilityClass(_ value: String) -> Bool {
        guard value.hasPrefix("ghost-compat-") else { return false }
        return validLowercaseToken(Substring(value), maximum: 96)
    }

    private static func validLowercaseToken(_ value: Substring, maximum: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximum else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48...57, 97...122:
                true
            default:
                false
            }
        }
    }
}
