import Foundation

struct NativeToolWebSource: Equatable, Sendable {
    let url: String
    let title: String?
    let snippet: String?
    let publishedAt: String?
}

/// Strict typed subset of the result-side official `card:'web'` envelope.
struct NativeToolWebView: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case search(answer: String?, sources: [NativeToolWebSource], truncated: Bool)
        case fetch(url: String, statusCode: Double, truncated: Bool)
    }

    let kind: Kind
}

/// Result-side-only equivalent of rc.2 `webCardModel`.
struct NativeWebCardPresentation: Equatable, Sendable {
    let kind: NativeToolWebView.Kind

    static func resolve(result: NativeToolWebView?, completed: Bool) -> NativeWebCardPresentation? {
        guard completed, let result else { return nil }
        return .init(kind: result.kind)
    }
}

/// Foundation decision used by native AppKit/SwiftUI links. It deliberately
/// admits http(s) only; untrusted other schemes always render as noninteractive
/// plain text, matching rc.2 WebBlock's external-link contract.
struct NativeSafeWebLink: Equatable, Sendable {
    let url: String
    let label: String
    let destination: URL?

    static func resolve(url: String, title: String?) -> NativeSafeWebLink {
        let parsed = URL(string: url)
        let destination: URL?
        if let parsed, let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            destination = parsed
        } else {
            destination = nil
        }
        let label: String
        if let title, !title.isEmpty {
            label = title
        } else if let hostname = parsed?.host, !hostname.isEmpty {
            label = hostname
        } else {
            label = url
        }
        return .init(url: url, label: label, destination: destination)
    }
}
