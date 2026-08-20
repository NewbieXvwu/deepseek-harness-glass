import Foundation
import XCTest

@testable import GlassCore

final class HostPathAPITests: XCTestCase {
    override func setUp() {
        super.setUp()
        HostPathURLProtocol.reset()
    }

    func testVerifiedHostOpenPathUsesTypedRPCAndHostOwnedResult() async throws {
        let apis = HarnessAPIs(
            baseURL: URL(string: "http://127.0.0.1:9777/")!,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(verifiedBuild)),
            diagnostics: HostDiagnosticRecorder(dshHome: "/tmp/test-dsh-home"),
            session: mockSession()
        )

        let response = try await apis.host.openPath("/workspace/project/src/main.swift")
        XCTAssertTrue(response.opened)
        let requests = HostPathURLProtocol.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.method, "host.openPath")
        XCTAssertEqual(requests.first?.payload, .object(["path": .string("/workspace/project/src/main.swift")]))
    }

    func testDiagnosticsOnlyHostRejectsOpenPathBeforeCarrierRequest() async {
        let apis = HarnessAPIs(
            baseURL: URL(string: "http://127.0.0.1:9777/")!,
            accessPolicy: .diagnosticsOnly,
            diagnostics: HostDiagnosticRecorder(dshHome: "/tmp/test-dsh-home"),
            session: mockSession()
        )

        do {
            _ = try await apis.host.openPath("/workspace/project/src/main.swift")
            XCTFail("unverified Hosts must never receive desktop open-path actions")
        } catch let error as DSHTransportError {
            guard case .unverifiedHostBuild = error else {
                return XCTFail("unexpected transport rejection: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(HostPathURLProtocol.requests().isEmpty)
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostPathURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var verifiedBuild: SupportedHostBuildCatalog.Build {
        SupportedHostBuildCatalog.Build(
            id: "test-verified-rc8",
            officialSourceCommit: "141eb6fef83422698aef7a981029e843e8161534",
            dshPackageVersion: "0.1.0-rc.8",
            webFrontendPackageVersion: "0.1.0-rc.8",
            nodeRuntimeVersion: "24",
            minimumAppVersion: "0.1.0",
            minimumMacOS: "26",
            ciRunner: "macos-26",
            minimumXcodeMajor: 26,
            protocolFixtureRevision: "test-fixture",
            uiSpecRevision: "test-spec",
            supportedArchitectures: ["arm64"],
            verifiedAt: nil,
            verificationState: "verified"
        )
    }
}

private final class HostPathURLProtocol: URLProtocol, @unchecked Sendable {
    private static let state = HostPathState()

    static func reset() { state.reset() }
    static func requests() -> [RPCClientRequest] { state.snapshot() }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "127.0.0.1"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let body = request.httpBody,
              let rpc = try? JSONDecoder().decode(RPCClientRequest.self, from: body)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.state.append(rpc)
        let response = RPCServerResponse(
            type: "server-response",
            rpcId: rpc.rpcId,
            result: .success(.object(["opened": .bool(true)]))
        )
        guard let data = try? JSONEncoder().encode(response),
              let url = request.url,
              let http = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class HostPathState: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [RPCClientRequest] = []

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        captured = []
    }

    func append(_ request: RPCClientRequest) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(request)
    }

    func snapshot() -> [RPCClientRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}
