import XCTest

@testable import GlassCore

final class SessionLogExporterTests: XCTestCase {
    override func tearDown() {
        ExportURLProtocol.state.reset()
        super.tearDown()
    }

    func testDownloadWritesSafeAttachmentNameAndResolvesFilenameCollisions() async throws {
        ExportURLProtocol.state.configure(status: 200, headers: [
            "Content-Type": "application/zip",
            "Content-Disposition": "attachment; filename*=UTF-8''session%20log.zip",
        ], body: Data("zip-contract".utf8))
        let destination = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let exporter = SessionLogExporter(session: makeSession(), destinationDirectory: destination)
        let url = URL(string: "http://127.0.0.1:9281/api/session.export?sessionId=contract-session&includeDescendants=true")!

        let first = try await exporter.export(url: url, fallbackFilename: "fallback.zip")
        let second = try await exporter.export(url: url, fallbackFilename: "fallback.zip")

        XCTAssertEqual(first.suggestedFilename, "session log.zip")
        XCTAssertEqual(second.suggestedFilename, "session log (2).zip")
        XCTAssertEqual(try Data(contentsOf: first.fileURL), Data("zip-contract".utf8))
        XCTAssertEqual(try Data(contentsOf: second.fileURL), Data("zip-contract".utf8))
        XCTAssertEqual(ExportURLProtocol.state.observedRequests().count, 2)
        XCTAssertEqual(ExportURLProtocol.state.observedRequests().first?.httpMethod, "GET")
    }

    func testUnverifiedHostCannotCreateNativeDownloadURL() async throws {
        let transport = DSHClientTransport(
            baseURL: URL(string: "http://127.0.0.1:9281/")!,
            accessPolicy: .diagnosticsOnly,
            session: makeSession()
        )
        do {
            _ = try await transport.downloadURL(sessionID: "contract-session")
            XCTFail("unverified Host must not expose a file-materializing download URL")
        } catch let error as DSHTransportError {
            guard case .unverifiedHostBuild = error else {
                return XCTFail("Expected unverifiedHostBuild, got \(error)")
            }
        }
    }

    func testDownloadMapsHostMissingSessionToHTTPTransportError() async throws {
        ExportURLProtocol.state.configure(status: 404, headers: ["Content-Type": "text/plain"], body: Data())
        let destination = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let exporter = SessionLogExporter(session: makeSession(), destinationDirectory: destination)
        let url = URL(string: "http://127.0.0.1:9281/api/session.export?sessionId=missing&includeDescendants=false")!

        do {
            _ = try await exporter.export(url: url, fallbackFilename: "missing.zip")
            XCTFail("404 session export must fail")
        } catch let error as DSHTransportError {
            guard case let .invalidHTTPStatus(status, _) = error else {
                return XCTFail("Expected invalidHTTPStatus, got \(error)")
            }
            XCTAssertEqual(status, 404)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExportURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-glass-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class ExportProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var headers: [String: String] = [:]
    private var body = Data()
    private var requests: [URLRequest] = []

    func configure(status: Int, headers: [String: String], body: Data) {
        lock.lock()
        self.status = status
        self.headers = headers
        self.body = body
        requests = []
        lock.unlock()
    }

    func response(for request: URLRequest) -> (Int, [String: String], Data) {
        lock.lock()
        requests.append(request)
        let result = (status, headers, body)
        lock.unlock()
        return result
    }

    func observedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func reset() {
        configure(status: 200, headers: [:], body: Data())
    }
}

private final class ExportURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = ExportProtocolState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = Self.state.response(for: request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: result.1)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.2)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
