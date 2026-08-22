import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Result of the host-only `DownloadsApi.sessionLog` GET carrier. The ZIP is
/// fully materialized inside a native local directory before it is exposed to
/// the native application, so no browser download delegate or browser-owned
/// temporary file is involved.
struct SessionLogExport: Equatable, Sendable {
    let fileURL: URL
    let suggestedFilename: String
    let responseContentType: String?
}

/// URLSessionDownloadTask based implementation of the official host-only GET
/// endpoint. This is intentionally separate from unary JSON RPC: the official
/// downloads domain produces an attachment stream, not an RPC envelope.
actor SessionLogExporter {
    private let session: URLSession
    private let fileManager: FileManager
    private let destinationDirectory: URL

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        destinationDirectory: URL? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.destinationDirectory = destinationDirectory ?? Self.defaultDestinationDirectory(fileManager: fileManager)
    }

    static func defaultDestinationDirectory(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root.appendingPathComponent("DeepSeek Harness", isDirectory: true)
    }

    func export(
        sessionID: String,
        includeDescendants: Bool = true,
        downloads: DownloadsAPI
    ) async throws -> SessionLogExport {
        let url = try await downloads.sessionLogURL(sessionID: sessionID, includeDescendants: includeDescendants)
        return try await export(url: url, fallbackFilename: "deepseek-session-\(safeFilenameComponent(sessionID)).zip")
    }

    /// Exposed for a URLProtocol-backed Core test; production features call the
    /// facade-taking overload above and never construct a download URL.
    func export(url: URL, fallbackFilename: String) async throws -> SessionLogExport {
        guard isTrustedLoopbackDownloadURL(url) else { throw DSHTransportError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("application/zip, application/octet-stream;q=0.9", forHTTPHeaderField: "Accept")

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let stagingURL = destinationDirectory.appendingPathComponent(".session-export-\(UUID().uuidString).partial", isDirectory: false)
        let (stagedURL, response) = try await download(request, stagingURL: stagingURL)
        defer { try? fileManager.removeItem(at: stagedURL) }
        guard let http = response as? HTTPURLResponse,
              isTrustedLoopbackDownloadURL(http.url ?? url) else {
            throw DSHTransportError.invalidEndpoint
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw DSHTransportError.invalidHTTPStatus(http.statusCode, body: "")
        }
        guard fileManager.fileExists(atPath: stagedURL.path) else {
            throw DSHTransportError.network("URLSessionDownloadTask did not produce a staging file")
        }

        let filename = suggestedFilename(from: http.value(forHTTPHeaderField: "Content-Disposition")) ?? fallbackFilename
        let destination = try reserveDestination(named: filename)
        do {
            try fileManager.moveItem(at: stagedURL, to: destination)
        } catch {
            throw DSHTransportError.network("Could not move exported session log into the native download directory: \(error.localizedDescription)")
        }
        return SessionLogExport(
            fileURL: destination,
            suggestedFilename: destination.lastPathComponent,
            responseContentType: http.value(forHTTPHeaderField: "Content-Type")
        )
    }

    private func isTrustedLoopbackDownloadURL(_ url: URL) -> Bool {
        url.scheme == "http"
            && url.host == "127.0.0.1"
            && url.user == nil
            && url.password == nil
            && (url.port ?? 0) > 0
    }

    private func reserveDestination(named proposedName: String) throws -> URL {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sanitized = safeFilenameComponent(proposedName)
        let fallback = sanitized.isEmpty ? "deepseek-session-log.zip" : sanitized
        let stem = (fallback as NSString).deletingPathExtension
        let ext = (fallback as NSString).pathExtension
        var attempt = 1
        while true {
            let suffix = attempt == 1 ? "" : " (\(attempt))"
            let name = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let candidate = destinationDirectory.appendingPathComponent(name, isDirectory: false)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            attempt += 1
        }
    }

    private func suggestedFilename(from contentDisposition: String?) -> String? {
        guard let contentDisposition else { return nil }
        let fields = contentDisposition.split(separator: ";", maxSplits: 8, omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        var fallbackFilename: String?
        for field in fields {
            let lower = field.lowercased()
            if lower.hasPrefix("filename*=") {
                let value = String(field.dropFirst("filename*=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let encoded = value.components(separatedBy: "''").last ?? value
                if let decoded = encoded.removingPercentEncoding, !decoded.isEmpty {
                    return safeFilenameComponent(decoded)
                }
            } else if lower.hasPrefix("filename=") && fallbackFilename == nil {
                let value = String(field.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty {
                    fallbackFilename = safeFilenameComponent(value)
                }
            }
        }
        return fallbackFilename
    }

    private func safeFilenameComponent(_ value: String) -> String {
        let leaf = (value as NSString).lastPathComponent
        return leaf.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\0", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func download(_ request: URLRequest, stagingURL: URL) async throws -> (URL, URLResponse) {
        let box = DownloadTaskBox()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request) { location, response, error in
                    if let error {
                        if (error as? URLError)?.code == .cancelled {
                            continuation.resume(throwing: DSHTransportError.cancelled)
                        } else {
                            continuation.resume(throwing: DSHTransportError.network(error.localizedDescription))
                        }
                        return
                    }
                    guard let location, let response else {
                        continuation.resume(throwing: DSHTransportError.network("Download completed without a URLSession response"))
                        return
                    }
                    do {
                        try FileManager.default.moveItem(at: location, to: stagingURL)
                        continuation.resume(returning: (stagingURL, response))
                    } catch {
                        continuation.resume(throwing: DSHTransportError.network("Could not retain URLSession download before its temporary file expired: \(error.localizedDescription)"))
                    }
                }
                box.install(task)
                task.resume()
            }
        }, onCancel: {
            box.cancel()
        })
    }
}

private final class DownloadTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?

    func install(_ task: URLSessionDownloadTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        task?.cancel()
        lock.unlock()
    }
}
