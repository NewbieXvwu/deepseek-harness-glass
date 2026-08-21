import Foundation
import XCTest

@testable import GlassCore

final class SSEClientTests: XCTestCase {
    func testRecordedStreamReconnectDropsReplayedRPCIDsAndLowSequences() async throws {
        let opener = RecordedSSEOpener(scripts: [
            [
                .frame(sessionEvent(rpcId: "event-1", sequence: 1)),
                .failure(.network("fixture-disconnect")),
            ],
            [
                .frame(sessionEvent(rpcId: "event-1-replay", sequence: 1)),
                .frame(projection(rpcId: "projection-3", sequence: 3)),
                .frame(projection(rpcId: "projection-2-replay", sequence: 2)),
                .frame(sessionEvent(rpcId: "event-2", sequence: 2)),
            ],
        ])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9234/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        let policy = SSEReconnectPolicy(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2)

        let collector = Task { () throws -> [RPCServerRequest] in
            var frames: [RPCServerRequest] = []
            let stream = await client.reconnectingStream(.mux, policy: policy)
            for try await frame in stream {
                frames.append(frame)
                if frames.count == 3 { return frames }
            }
            return frames
        }
        let frames = try await collector.value

        XCTAssertEqual(frames.map(\.rpcId), ["event-1", "projection-3", "event-2"])
        XCTAssertEqual(frames.map(\.method), ["session/event", "session/projection", "session/event"])
        XCTAssertEqual(opener.openedEndpoints(), [.mux, .mux])
        let traces = await client.recentReconnectTraces()
        XCTAssertTrue(traces.contains { $0.outcome == .reconnecting && $0.errorCategory == "network" })
        XCTAssertTrue(traces.contains { $0.outcome == .opened })
    }

    func testRawReconnectFixtureDropsDuplicateSequenceAcrossStreamReopen() async throws {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = tryUnwrap(fixture.cases.first(where: { $0.id == "reconnect-duplicate-sequence" }))
        let opener = RecordedSSEOpener(scripts: [
            [
                .frame(replaySessionEvent(rpcId: "fixture-40", event: replay.events[0])),
                .frame(replaySessionEvent(rpcId: "fixture-41", event: replay.events[1])),
                .frame(replaySessionEvent(rpcId: "fixture-42", event: replay.events[2])),
                .failure(.network("fixture-reconnect")),
            ],
            [
                .frame(replaySessionEvent(rpcId: "fixture-42-replay", event: replay.events[3])),
                .frame(replaySessionEvent(rpcId: "fixture-43", event: replay.events[4])),
            ],
        ])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9235/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        let collector = Task { () throws -> [RPCServerRequest] in
            var frames: [RPCServerRequest] = []
            let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
            for try await frame in stream {
                frames.append(frame)
                if frames.count == 4 { return frames }
            }
            return frames
        }
        let frames = try await collector.value

        XCTAssertEqual(frames.map { $0.payload.objectValue?["event"]?.objectValue?["seq"]?.numberValue }, [40, 41, 42, 43])
        XCTAssertEqual(frames.map(\.rpcId), ["fixture-40", "fixture-41", "fixture-42", "fixture-43"])
        XCTAssertEqual(opener.openedEndpoints(), [.mux, .mux])
    }

    func testFinalCancellationStopsRetryLoopWithoutFurtherOpen() async throws {
        let opener = RecordedSSEOpener(scripts: [[.failure(.network("fixture-disconnect"))]])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9234/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        let policy = SSEReconnectPolicy(initialDelay: 1, maximumDelay: 1, multiplier: 1)

        let consumer = Task { () -> [RPCServerRequest] in
            let stream = await client.reconnectingStream(.host, policy: policy)
            var received: [RPCServerRequest] = []
            do {
                for try await frame in stream { received.append(frame) }
            } catch {
                XCTFail("final cancellation must not surface a retry error: \(error)")
            }
            return received
        }
        try await waitForOpenCount(opener, expected: 1)
        consumer.cancel()
        let received = await consumer.value
        XCTAssertEqual(received.count, 0)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(opener.openedEndpoints(), [.host])
        let traces = await client.recentReconnectTraces()
        XCTAssertEqual(traces.last?.outcome, .cancelled)
    }

    func testOfficialSSEParserDropsMalformedFramesAndPreservesValidServerRequest() throws {
        var parser = SSEFrameParser(decoder: JSONDecoder())
        XCTAssertNil(parser.consume(line: ": connected"))
        XCTAssertNil(parser.consume(line: "data: not-json"))
        XCTAssertNil(parser.consume(line: ""))
        XCTAssertNil(parser.consume(line: "data: {\"type\":\"server-response\",\"rpcId\":\"bad\"}"))
        XCTAssertNil(parser.consume(line: ""))

        let wire = try JSONEncoder().encode(sessionEvent(rpcId: "valid", sequence: 8))
        XCTAssertNil(parser.consume(line: "data: " + String(decoding: wire, as: UTF8.self)))
        let valid = parser.consume(line: "")
        XCTAssertEqual(valid?.type, "server-request")
        XCTAssertEqual(valid?.rpcId, "valid")
        XCTAssertEqual(valid?.method, "session/event")
    }

    private func sessionEvent(rpcId: String, sequence: Int) -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: rpcId,
            method: "session/event",
            payload: .object([
                "type": .string("session/event"),
                "sessionId": .string("fixture-session"),
                "event": .object([
                    "type": .string("turn/start"),
                    "seq": .number(Double(sequence)),
                    "time": .number(1),
                    "data": .object([:]),
                ]),
            ])
        )
    }

    private func replaySessionEvent(rpcId: String, event: JSONValue) -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: rpcId,
            method: "session/event",
            payload: .object([
                "type": .string("session/event"),
                "sessionId": .string("fixture-session"),
                "event": event,
            ])
        )
    }

    private func projection(rpcId: String, sequence: Int) -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: rpcId,
            method: "session/projection",
            payload: .object([
                "type": .string("session/projection"),
                "sessionId": .string("fixture-session"),
                "key": .string("title"),
                "value": .string("fixture"),
                "seq": .number(Double(sequence)),
            ])
        )
    }

    private func waitForOpenCount(_ opener: RecordedSSEOpener, expected: Int) async throws {
        for _ in 0 ..< 100 {
            if opener.openedEndpoints().count >= expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("recorded SSE opener did not open \(expected) stream(s) before timeout")
    }
}

private enum RecordedSSEElement: Sendable {
    case frame(RPCServerRequest)
    case failure(DSHTransportError)
}

private final class RecordedSSEOpener: @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [[RecordedSSEElement]]
    private var endpoints: [DSHSSEEndpoint] = []

    init(scripts: [[RecordedSSEElement]]) {
        self.scripts = scripts
    }

    func open(_ endpoint: DSHSSEEndpoint) -> SSEFrameStream {
        lock.lock()
        endpoints.append(endpoint)
        let script = scripts.isEmpty ? [.failure(.network("recording-exhausted"))] : scripts.removeFirst()
        lock.unlock()
        return SSEFrameStream { continuation in
            for element in script {
                switch element {
                case let .frame(frame): continuation.yield(frame)
                case let .failure(error):
                    continuation.finish(throwing: error)
                    return
                }
            }
            continuation.finish()
        }
    }

    func openedEndpoints() -> [DSHSSEEndpoint] {
        lock.lock()
        defer { lock.unlock() }
        return endpoints
    }
}
