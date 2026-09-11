import Foundation

/// Response-side counterpart to `GhostPlaneLoopbackPolicy`.
public struct GhostPlaneResponsePolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case allowSkeletonDocument
        case allowPluginResource(pluginID: String)
        case allowPluginCombo(pluginIDs: [String], sourceMap: Bool)
        case deny(Denial)
    }

    public enum Denial: Equatable, Sendable {
        case requestDenied(GhostPlaneLoopbackPolicy.Denial)
        case responseDenied(GhostPlaneLoopbackPolicy.Denial)
        case redirect
        case nonSuccessStatus
        case missingMIMEType
        case unexpectedMIMEType
        case pathMIMEMismatch
    }

    private let loopback: GhostPlaneLoopbackPolicy
    public init(loopback: GhostPlaneLoopbackPolicy) { self.loopback = loopback }

    public func decision(requestURL: URL, responseURL: URL, statusCode: Int, mimeType: String?) -> Decision {
        switch loopback.decision(for: requestURL) {
        case .allowSkeletonDocument, .allowPluginResource, .allowPluginCombo: break
        case .deny(let reason): return .deny(.requestDenied(reason))
        }
        guard requestURL == responseURL else { return .deny(.redirect) }
        guard (200...299).contains(statusCode) else { return .deny(.nonSuccessStatus) }
        let normalized = mimeType?.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let normalized, !normalized.isEmpty else { return .deny(.missingMIMEType) }

        switch loopback.decision(for: responseURL) {
        case .deny(let reason): return .deny(.responseDenied(reason))
        case .allowSkeletonDocument:
            return normalized == "text/html" ? .allowSkeletonDocument : .deny(.unexpectedMIMEType)
        case .allowPluginCombo(let ids, let sourceMap):
            if sourceMap { return normalized == "application/json" ? .allowPluginCombo(pluginIDs: ids, sourceMap: true) : .deny(.unexpectedMIMEType) }
            return javascriptMIMEs.contains(normalized) ? .allowPluginCombo(pluginIDs: ids, sourceMap: false) : .deny(.unexpectedMIMEType)
        case .allowPluginResource(let pluginID):
            guard allowedPluginMIME(normalized) else { return .deny(.unexpectedMIMEType) }
            guard pathMIMEMatches(responseURL.path, mime: normalized) else { return .deny(.pathMIMEMismatch) }
            return .allowPluginResource(pluginID: pluginID)
        }
    }

    private let javascriptMIMEs: Set<String> = ["text/javascript", "application/javascript", "application/ecmascript"]
    private func allowedPluginMIME(_ mime: String) -> Bool {
        javascriptMIMEs.contains(mime) || ["text/css", "application/json", "image/png", "image/jpeg", "image/gif", "image/webp", "font/woff2", "application/font-woff2"].contains(mime)
    }
    private func pathMIMEMatches(_ path: String, mime: String) -> Bool {
        let lower = path.lowercased()
        if lower.hasSuffix(".js") { return javascriptMIMEs.contains(mime) }
        if lower.hasSuffix(".css") { return mime == "text/css" }
        if lower.hasSuffix(".json") { return mime == "application/json" }
        if lower.hasSuffix(".png") { return mime == "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return mime == "image/jpeg" }
        if lower.hasSuffix(".gif") { return mime == "image/gif" }
        if lower.hasSuffix(".webp") { return mime == "image/webp" }
        if lower.hasSuffix(".woff2") { return ["font/woff2", "application/font-woff2"].contains(mime) }
        return false
    }
}
