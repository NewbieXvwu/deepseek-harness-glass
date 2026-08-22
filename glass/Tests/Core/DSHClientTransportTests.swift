import Foundation
import XCTest

@testable import GlassCore

final class DSHClientTransportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RPCTransportURLProtocol.reset()
    }

    override func tearDown() {
        RPCTransportURLProtocol.reset()
        super.tearDown()
    }

    func testOneHundredConcurrentRPCsPreservePayloadCorrelationAndUniqueRPCIDs() async throws {
        RPCTransportURLProtocol.configure(delay: 0.01, responseMode: .echo)
        let transport = DSHClientTransport(
            baseURL: URL(string: "http://127.0.0.1:9234/")!,
            accessPolicy: .diagnosticsOnly,
            session: makeMockSession()
        )

        let responses = try await withThrowingTaskGroup(of: RPCServerResponse.self, returning: [RPCServerResponse].self) { group in
            for index in 0 ..< 100 {
                group.addTask {
                    try await transport.call(
                        method: "host.describe",
                        payload: .object(["requestIndex": .number(Double(index))])
                    )
                }
            }
            var collected: [RPCServerResponse] = []
            for try await response in group {
                collected.append(response)
            }
            return collected
        }

        XCTAssertEqual(responses.count, 100)
        let requests = RPCTransportURLProtocol.capturedRequests()
        XCTAssertEqual(requests.count, 100)
        XCTAssertEqual(Set(requests.map(\.rpcId)).count, 100, "every concurrent request must reserve a unique in-flight rpcId")
        XCTAssertEqual(Set(responses.map(\.rpcId)), Set(requests.map(\.rpcId)))
        XCTAssertEqual(
            Set(responses.compactMap(requestIndex)),
            Set((0 ..< 100).map(Double.init)),
            "each response must remain correlated to its originating payload"
        )

        let traces = await transport.recentCallTraces()
        XCTAssertEqual(traces.count, 100)
        XCTAssertTrue(traces.allSatisfy { $0.outcome == .succeeded && $0.rpcId != nil })
        XCTAssertEqual(Set(traces.compactMap(\.rpcId)).count, 100)
    }

    func testDuplicateInFlightRPCIDIsRejectedWithoutSecondCarrierRequest() async throws {
        RPCTransportURLProtocol.configure(delay: 0.15, responseMode: .echo)
        let transport = DSHClientTransport(
            baseURL: URL(string: "http://127.0.0.1:9234/")!,
            accessPolicy: .diagnosticsOnly,
            session: makeMockSession(),
            rpcIDGenerator: { "reused-rpc-id" }
        )
        let first = Task {
            try await transport.call(method: "host.describe", payload: .object([:]))
        }
        try await waitForCarrierRequestCount(1)

        do {
            _ = try await transport.call(method: "host.describe", payload: .object([:]))
            XCTFail("a duplicate in-flight rpcId must be rejected")
        } catch let error as DSHTransportError {
            XCTAssertEqual(error, .duplicateRPCID("reused-rpc-id"))
        }
        _ = try await first.value

        XCTAssertEqual(RPCTransportURLProtocol.capturedRequests().count, 1)
        let traces = await transport.recentCallTraces()
        XCTAssertEqual(traces.map(\.outcome), [.rejected, .succeeded])
        XCTAssertEqual(traces.first?.rpcId, nil)
        XCTAssertEqual(traces.last?.rpcId, "reused-rpc-id")
    }

    func testMismatchedResponseRPCIDIsNeverDeliveredToCaller() async throws {
        RPCTransportURLProtocol.configure(delay: 0, responseMode: .mismatchedID)
        let transport = DSHClientTransport(
            baseURL: URL(string: "http://127.0.0.1:9234/")!,
            accessPolicy: .diagnosticsOnly,
            session: makeMockSession(),
            rpcIDGenerator: { "expected-rpc-id" }
        )

        do {
            _ = try await transport.call(method: "host.describe", payload: .object([:]))
            XCTFail("a response with another rpcId must never be delivered")
        } catch let error as DSHTransportError {
            XCTAssertEqual(error, .mismatchedRPCID(expected: "expected-rpc-id", actual: "crossed-rpc-id"))
        }
        let traces = await transport.recentCallTraces()
        XCTAssertEqual(traces.count, 1)
        XCTAssertEqual(traces[0].outcome, .failed)
        XCTAssertEqual(traces[0].rpcId, "expected-rpc-id")
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RPCTransportURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestIndex(_ response: RPCServerResponse) -> Double? {
        guard case let .success(value) = response.result,
              case let .object(object) = value,
              case let .number(index)? = object["requestIndex"] else {
            return nil
        }
        return index
    }

    private func waitForCarrierRequestCount(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0 ..< 100 {
            if RPCTransportURLProtocol.capturedRequests().count >= expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("mock carrier did not receive \(expected) request(s) before timeout", file: file, line: line)
    }
}

private final class RPCTransportURLProtocol: URLProtocol, @unchecked Sendable {
    enum ResponseMode: Equatable, Sendable {
        case echo
        case mismatchedID
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [RPCClientRequest] = []
        private var delay: TimeInterval = 0
        private var responseMode: ResponseMode = .echo

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            requests = []
            delay = 0
            responseMode = .echo
        }

        func configure(delay: TimeInterval, responseMode: ResponseMode) {
            lock.lock()
            defer { lock.unlock() }
            self.delay = delay
            self.responseMode = responseMode
        }

        func append(_ request: RPCClientRequest) -> (delay: TimeInterval, responseMode: ResponseMode) {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            return (delay, responseMode)
        }

        func snapshot() -> [RPCClientRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }
    }

    private static let state = State()

    static func reset() { state.reset() }
    static func configure(delay: TimeInterval, responseMode: ResponseMode) { state.configure(delay: delay, responseMode: responseMode) }
    static func capturedRequests() -> [RPCClientRequest] { state.snapshot() }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "127.0.0.1"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let body = requestBodyData() else {
            fail(URLError(.badServerResponse))
            return
        }
        do {
            let request = try JSONDecoder().decode(RPCClientRequest.self, from: body)
            let behavior = Self.state.append(request)
            if behavior.delay > 0 {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + behavior.delay) { [weak self] in
                    self?.deliver(request, mode: behavior.responseMode)
                }
            } else {
                deliver(request, mode: behavior.responseMode)
            }
        } catch {
            fail(error)
        }
    }

    override func stopLoading() {}

    private func requestBodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func deliver(_ request: RPCClientRequest, mode: ResponseMode) {
        let responseID = mode == .echo ? request.rpcId : "crossed-rpc-id"
        let payload: JSONValue
        switch mode {
        case .echo: payload = request.payload
        case .mismatchedID: payload = .object([:])
        }
        let response = RPCServerResponse(type: "server-response", rpcId: responseID, result: .success(payload))
        do {
            let data = try JSONEncoder().encode(response)
            guard let url = self.request.url,
                  let http = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                fail(URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }
}
