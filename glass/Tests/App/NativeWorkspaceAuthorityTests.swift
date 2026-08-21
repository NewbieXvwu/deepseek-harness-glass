import Foundation
import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeWorkspaceAuthorityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WorkspaceAuthorityURLProtocol.reset()
    }

    func testSupersededDelayedHostListsCannotReviveOldWorkspaceAuthority() async throws {
        let store = NativeWorkspaceStore()
        let apis = HarnessAPIs(
            baseURL: URL(string: "http://127.0.0.1:9788/")!,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(verifiedBuild)),
            diagnostics: HostDiagnosticRecorder(dshHome: "/tmp/t72-workspace-authority"),
            session: mockSession()
        )

        // The first generation is deliberately delayed and ignores cancellation
        // at the carrier layer, emulating a stale Host echo after a newer browser
        // refresh has already completed.
        store.refresh(using: apis)
        try await waitForRequestCount(2)
        store.refresh(using: apis)
        try await waitForRequestCount(4)

        try await eventually {
            store.phase == .ready
                && store.snapshot.workspaces.map(\.workspaceId) == ["new-workspace"]
                && store.snapshot.sessions.map(\.sessionId) == ["new-session"]
        }

        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.snapshot.workspaces.map(\.workspaceId), ["new-workspace"])
        XCTAssertEqual(store.snapshot.sessions.map(\.sessionId), ["new-session"])
        let methods = WorkspaceAuthorityURLProtocol.capturedMethods()
        XCTAssertEqual(methods.filter { $0 == "workspace.list" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session.list" }.count, 2)
    }

    func testArchiveReceiptLeavesWorkspaceSnapshotUntouchedUntilHostListRefresh() async throws {
        let store = NativeWorkspaceStore()
        let apis = HarnessAPIs(
            baseURL: URL(string: "http://127.0.0.1:9788/")!,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(verifiedBuild)),
            diagnostics: HostDiagnosticRecorder(dshHome: "/tmp/t72-workspace-archive-authority"),
            session: mockSession()
        )

        store.refresh(using: apis)
        try await eventually {
            store.phase == .ready
                && store.snapshot.workspaces.map(\.workspaceId) == ["old-workspace"]
                && store.snapshot.sessions.map(\.sessionId) == ["old-session"]
        }

        let receipt = try await apis.workspaces.archiveSession(sessionID: "old-session")
        XCTAssertEqual(receipt.archivedSessionIds, ["old-session"])
        // A mutation receipt proves only that Host accepted the operation. The
        // local browser remains the last complete Host list until a refresh.
        XCTAssertEqual(store.snapshot.workspaces.map(\.workspaceId), ["old-workspace"])
        XCTAssertEqual(store.snapshot.sessions.map(\.sessionId), ["old-session"])
        XCTAssertTrue(store.snapshot.archivedSessionIDs.isEmpty)

        store.refresh(using: apis)
        try await eventually {
            store.phase == .ready
                && store.snapshot.workspaces.map(\.workspaceId) == ["new-workspace"]
                && store.snapshot.sessions.map(\.sessionId) == ["new-session"]
        }
    }

    func testCreateReceiptLeavesWorkspaceSnapshotUntouchedUntilHostListRefresh() async throws {
        let store = NativeWorkspaceStore()
        let apis = HarnessAPIs(
            baseURL: URL(string: "http://127.0.0.1:9788/")!,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(verifiedBuild)),
            diagnostics: HostDiagnosticRecorder(dshHome: "/tmp/t72-workspace-create-authority"),
            session: mockSession()
        )

        store.refresh(using: apis)
        try await eventually {
            store.phase == .ready
                && store.snapshot.workspaces.map(\.workspaceId) == ["old-workspace"]
        }

        let receipt = try await apis.workspaces.create(path: "/new")
        XCTAssertTrue(receipt.created)
        XCTAssertEqual(receipt.workspace.workspaceId, "new-workspace")
        // The receipt is not a browser snapshot. Do not splice it into the
        // local tree; a complete Host list defines visibility and ordering.
        XCTAssertEqual(store.snapshot.workspaces.map(\.workspaceId), ["old-workspace"])
        XCTAssertEqual(store.snapshot.sessions.map(\.sessionId), ["old-session"])

        store.refresh(using: apis)
        try await eventually {
            store.phase == .ready
                && store.snapshot.workspaces.map(\.workspaceId) == ["new-workspace"]
                && store.snapshot.sessions.map(\.sessionId) == ["new-session"]
        }
    }

    func testWorkspaceChangedHostEventRefreshesCompleteAuthorityWithoutApplyingPayload() async throws {
        let store = NativeWorkspaceStore()
        let apis = HarnessAPIs(
            baseURL: URL(string: "http://127.0.0.1:9788/")!,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(verifiedBuild)),
            diagnostics: HostDiagnosticRecorder(dshHome: "/tmp/t72-workspace-host-change"),
            session: mockSession()
        )

        store.refresh(using: apis)
        try await eventually {
            store.phase == .ready
                && store.snapshot.workspaces.map(\.workspaceId) == ["old-workspace"]
                && store.snapshot.sessions.map(\.sessionId) == ["old-session"]
        }

        // RC8 emits `host/workspace-changed`. Its payload is a notification,
        // not a browser snapshot, and must never be spliced into the native tree.
        store.receiveHostEvent(
            RPCServerRequest(
                type: "server-request",
                rpcId: "workspace-change",
                method: "host/workspace-changed",
                payload: .object(["workspace": .object(["workspaceId": .string("payload-only")])])
            ),
            using: apis
        )

        try await waitForRequestCount(4)
        try await eventually {
            store.phase == .ready
                && store.snapshot.workspaces.map(\.workspaceId) == ["new-workspace"]
                && store.snapshot.sessions.map(\.sessionId) == ["new-session"]
        }
        let methods = WorkspaceAuthorityURLProtocol.capturedMethods()
        XCTAssertEqual(methods.filter { $0 == "workspace.list" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session.list" }.count, 2)
        XCTAssertFalse(store.snapshot.workspaces.map(\.workspaceId).contains("payload-only"))
    }

    func testUnrelatedHostEventDoesNotRefreshWorkspaceAuthority() async throws {
        let store = NativeWorkspaceStore()
        let apis = HarnessAPIs(
            baseURL: URL(string: "http://127.0.0.1:9788/")!,
            accessPolicy: HostRPCAccessPolicy(trust: .verified(verifiedBuild)),
            diagnostics: HostDiagnosticRecorder(dshHome: "/tmp/t72-workspace-unrelated-event"),
            session: mockSession()
        )

        store.receiveHostEvent(
            RPCServerRequest(type: "server-request", rpcId: "ignored", method: "host/diagnostics", payload: .null),
            using: apis
        )
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(WorkspaceAuthorityURLProtocol.capturedMethods().isEmpty)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.snapshot.workspaces, [])
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkspaceAuthorityURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func waitForRequestCount(_ count: Int) async throws {
        for _ in 0 ..< 100 {
            if WorkspaceAuthorityURLProtocol.capturedMethods().count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("expected \(count) workspace authority requests")
    }

    private func eventually(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0 ..< 100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("newer Host workspace authority did not become visible")
    }

    private var verifiedBuild: SupportedHostBuildCatalog.Build {
        SupportedHostBuildCatalog.Build(
            id: "test-verified-rc8",
            officialSourceCommit: "528c682e061696f5a160f363f236ecbf53cbd006",
            dshPackageVersion: "0.1.1-rc.1",
            webFrontendPackageVersion: "0.1.1-rc.1",
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

private final class WorkspaceAuthorityURLProtocol: URLProtocol, @unchecked Sendable {
    private enum Generation {
        case stale
        case current
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var methods: [String] = []

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            methods = []
        }

        func append(_ method: String) -> Generation {
            lock.lock()
            defer { lock.unlock() }
            methods.append(method)
            // `NativeWorkspaceStore.refresh` starts workspace.list and
            // session.list concurrently. The first pair is stale by contract.
            return methods.count <= 2 ? .stale : .current
        }

        func snapshot() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return methods
        }
    }

    private static let state = State()

    static func reset() { state.reset() }
    static func capturedMethods() -> [String] { state.snapshot() }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "127.0.0.1"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let body = request.httpBody ?? Self.readBody(from: request.httpBodyStream),
              let rpc = try? JSONDecoder().decode(RPCClientRequest.self, from: body)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let generation = Self.state.append(rpc.method)
        let delay: TimeInterval = generation == .stale ? 0.20 : 0
        if delay > 0 {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.deliver(rpc, generation: generation)
            }
        } else {
            deliver(rpc, generation: generation)
        }
    }

    override func stopLoading() {
        // Intentional: a stale carrier may still finish after task cancellation.
        // The store's cancellation fence must reject it before publication.
    }

    /// Foundation may materialize a URLProtocol request body as an input stream
    /// on macOS, even when the originating `URLRequest` used `httpBody`.
    /// Consume either carrier so this authority-race test exercises the RPC
    /// responses rather than a platform-specific test-double decoding failure.
    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private func deliver(_ rpc: RPCClientRequest, generation: Generation) {
        let suffix = generation == .stale ? "old" : "new"
        let value: JSONValue
        switch rpc.method {
        case "workspace.list":
            value = .object([
                "items": .array([.object([
                    "workspaceId": .string("\(suffix)-workspace"),
                    "path": .string("/\(suffix)"),
                    "title": .string("\(suffix)"),
                    "sessionIds": .array([.string("\(suffix)-session")]),
                    "createdAt": .string("2026-01-01T00:00:00.000Z"),
                    "updatedAt": .string("2026-01-01T00:00:00.000Z"),
                ])]),
                "archivedSessionIds": .array([]),
            ])
        case "session.list":
            value = .object([
                "items": .array([.object([
                    "sessionId": .string("\(suffix)-session"),
                    "updatedAt": .number(generation == .stale ? 1 : 2),
                    "running": .bool(false),
                    "blank": .bool(false),
                    "cwd": .string("/\(suffix)"),
                ])]),
            ])
        case "workspace.archiveSession":
            value = .object(["archivedSessionIds": .array([.string("old-session")])])
        case "workspace.create":
            value = .object([
                "workspace": .object([
                    "workspaceId": .string("new-workspace"),
                    "path": .string("/new"),
                    "title": .string("new"),
                    "sessionIds": .array([.string("new-session")]),
                    "createdAt": .string("2026-01-01T00:00:00.000Z"),
                    "updatedAt": .string("2026-01-01T00:00:00.000Z"),
                ]),
                "created": .bool(true),
            ])
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = RPCServerResponse(type: "server-response", rpcId: rpc.rpcId, result: .success(value))
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
}
