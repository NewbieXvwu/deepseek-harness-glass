import Foundation
import WebKit

/// Host-private file leases used only to materialize standard browser File
/// objects for paste/drop events. Plugins receive File bytes through WebKit's
/// normal event objects; native filesystem paths never cross the page boundary.
final class GhostPlaneTemporaryFileStore: NSObject, WKURLSchemeHandler {
    static let scheme = "dsh-glass-attachment"

    struct Descriptor: Equatable, Sendable {
        let id: UUID
        let url: URL
        let suggestedName: String
        let mediaType: String

        var rendererPayload: [String: String] {
            [
                "id": id.uuidString,
                "url": url.absoluteString,
                "suggestedName": suggestedName,
                "mediaType": mediaType,
            ]
        }
    }

    private struct Lease {
        let fileURL: URL
        let descriptor: Descriptor
    }

    private let root: URL
    private let lock = NSLock()
    private var leases: [UUID: Lease] = [:]

    override init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekHarnessGlass", isDirectory: true)
            .appendingPathComponent("GhostPlaneAttachments", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func lease(data: Data, id: UUID, suggestedName: String, mediaType: String) throws -> Descriptor {
        guard Self.validName(suggestedName), Self.validMediaType(mediaType) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fileURL = root.appendingPathComponent(id.uuidString, isDirectory: false)
        try data.write(to: fileURL, options: [.atomic])
        return install(fileURL: fileURL, id: id, suggestedName: suggestedName, mediaType: mediaType)
    }

    func lease(fileURL source: URL, id: UUID, suggestedName: String, mediaType: String) throws -> Descriptor {
        guard source.isFileURL, Self.validName(suggestedName), Self.validMediaType(mediaType) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let destination = root.appendingPathComponent(id.uuidString, isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return install(fileURL: destination, id: id, suggestedName: suggestedName, mediaType: mediaType)
    }

    func descriptor(for id: UUID) -> Descriptor? {
        lock.lock(); defer { lock.unlock() }
        return leases[id]?.descriptor
    }

    func revoke(_ id: UUID) {
        lock.lock()
        let lease = leases.removeValue(forKey: id)
        lock.unlock()
        if let lease { try? FileManager.default.removeItem(at: lease.fileURL) }
    }

    func revokeAll() {
        lock.lock()
        let old = leases.values.map(\.fileURL)
        leases.removeAll()
        lock.unlock()
        for fileURL in old { try? FileManager.default.removeItem(at: fileURL) }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.scheme == Self.scheme,
              let rawID = requestURL.host,
              let id = UUID(uuidString: rawID)
        else {
            urlSchemeTask.didFailWithError(CocoaError(.fileReadNoSuchFile))
            return
        }
        lock.lock()
        let lease = leases[id]
        lock.unlock()
        guard let lease, let data = try? Data(contentsOf: lease.fileURL, options: .mappedIfSafe) else {
            urlSchemeTask.didFailWithError(CocoaError(.fileReadNoSuchFile))
            return
        }
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": lease.descriptor.mediaType,
                "Content-Length": String(data.count),
                "Cache-Control": "no-store",
                "Access-Control-Allow-Origin": "*",
            ]
        ) ?? URLResponse(
            url: requestURL,
            mimeType: lease.descriptor.mediaType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func install(fileURL: URL, id: UUID, suggestedName: String, mediaType: String) -> Descriptor {
        let descriptor = Descriptor(
            id: id,
            url: URL(string: "\(Self.scheme)://\(id.uuidString)")!,
            suggestedName: suggestedName,
            mediaType: mediaType
        )
        lock.lock()
        let old = leases.updateValue(.init(fileURL: fileURL, descriptor: descriptor), forKey: id)
        lock.unlock()
        if let old, old.fileURL != fileURL { try? FileManager.default.removeItem(at: old.fileURL) }
        return descriptor
    }

    private static func validName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 255 && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    private static func validMediaType(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 43, 45, 46, 47, 48...57, 65...90, 97...122: true
            default: false
            }
        }
    }
}
