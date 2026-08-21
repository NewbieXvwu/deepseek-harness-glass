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

    func testSequenceFenceDoesNotCrossDeduplicateDifferentSessions() async throws {
        let opener = RecordedSSEOpener(scripts: [[
            .frame(sessionEvent(rpcId: "session-a-seq-1", sequence: 1, sessionID: "fixture-session-a")),
            .frame(sessionEvent(rpcId: "session-b-seq-1", sequence: 1, sessionID: "fixture-session-b")),
        ]])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9237/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        var frames: [RPCServerRequest] = []
        let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
        for try await frame in stream { frames.append(frame) }

        XCTAssertEqual(frames.map(\.rpcId), ["session-a-seq-1", "session-b-seq-1"])
        XCTAssertEqual(frames.map { $0.payload.objectValue?["sessionId"]?.stringValue }, ["fixture-session-a", "fixture-session-b"])
    }

    func testRawReconnectFixtureDropsOutOfOrderSequenceWithoutBlockingNewerFrame() async throws {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = tryUnwrap(fixture.cases.first(where: { $0.id == "reconnect-duplicate-sequence" }))
        let opener = RecordedSSEOpener(scripts: [[
            .frame(replaySessionEvent(rpcId: "fixture-40", event: replay.events[0])),
            .frame(replaySessionEvent(rpcId: "fixture-42", event: replay.events[2])),
            .frame(replaySessionEvent(rpcId: "fixture-41-late", event: replay.events[1])),
            .frame(replaySessionEvent(rpcId: "fixture-43", event: replay.events[4])),
        ]])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9236/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        var frames: [RPCServerRequest] = []
        let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
        for try await frame in stream { frames.append(frame) }

        XCTAssertEqual(frames.map { $0.payload.objectValue?["event"]?.objectValue?["seq"]?.numberValue }, [40, 42, 43])
        XCTAssertEqual(frames.map(\.rpcId), ["fixture-40", "fixture-42", "fixture-43"])
        XCTAssertEqual(opener.openedEndpoints(), [.mux])
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

    func testHighFrequencyOutOfOrderStreamDropsLateFrameWithoutBlockingNewTail() async throws {
        var script = (1 ... 1_000).map { sequence in
            RecordedSSEElement.frame(sessionEvent(rpcId: "live-\(sequence)", sequence: sequence))
        }
        script.append(.frame(sessionEvent(rpcId: "late-1000", sequence: 1_000)))
        script.append(.frame(sessionEvent(rpcId: "live-1001", sequence: 1_001)))
        let opener = RecordedSSEOpener(scripts: [script])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9238/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )

        var frames: [RPCServerRequest] = []
        let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
        for try await frame in stream { frames.append(frame) }

        XCTAssertEqual(frames.count, 1_001)
        XCTAssertEqual(frames.first?.rpcId, "live-1")
        XCTAssertEqual(frames.last?.rpcId, "live-1001")
        XCTAssertFalse(frames.map(\.rpcId).contains("late-1000"))
        XCTAssertEqual(opener.openedEndpoints(), [.mux])
    }

    func testHighFrequencyConsumerTerminationCancelsCarrierWithoutOpeningReconnect() async throws {
        let firstFrameProduced = expectation(description: "high-frequency carrier produces first frame")
        let producerStopped = expectation(description: "carrier producer observes stream termination")
        let producerCancelled = expectation(description: "carrier producer observes cancellation after consumer termination")
        let gate = RecoveryGate()
        let opener = RecordedSSEOpener(scripts: [])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9239/")!,
            testStreamOpener: { endpoint in
                // Count the physical open using the existing deterministic test
                // helper, then replace its exhausted stream with a cancellable
                // high-frequency carrier.
                _ = opener.open(endpoint)
                return SSEFrameStream { continuation in
                    let producer = Task {
                        for sequence in 1 ... 10_000 {
                            if Task.isCancelled { break }
                            continuation.yield(highFrequencySessionEvent(sequence: sequence))
                            if sequence == 1 {
                                firstFrameProduced.fulfill()
                                await gate.wait()
                                if Task.isCancelled { producerCancelled.fulfill() }
                            }
                        }
                        producerStopped.fulfill()
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in producer.cancel() }
                }
            }
        )

        let consumer = Task { () throws -> [RPCServerRequest] in
            var frames: [RPCServerRequest] = []
            let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
            for try await frame in stream {
                frames.append(frame)
                if frames.count == 1 { return frames }
            }
            return frames
        }
        await fulfillment(of: [firstFrameProduced], timeout: 1)
        let frames = try await consumer.value
        await fulfillment(of: [producerCancelled, producerStopped], timeout: 1)

        XCTAssertEqual(frames.map(\.rpcId), ["high-frequency-1"])
        XCTAssertEqual(opener.openedEndpoints(), [.mux])
        let traces = await client.recentReconnectTraces()
        XCTAssertEqual(traces.last?.outcome, .cancelled)
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

    private func sessionEvent(rpcId: String, sequence: Int, sessionID: String = "fixture-session") -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: rpcId,
            method: "session/event",
            payload: .object([
                "type": .string("session/event"),
                "sessionId": .string(sessionID),
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

private func highFrequencySessionEvent(sequence: Int) -> RPCServerRequest {
    RPCServerRequest(
        type: "server-request",
        rpcId: "high-frequency-\(sequence)",
        method: "session/event",
        payload: .object([
            "type": .string("session/event"),
            "sessionId": .string("high-frequency-session"),
            "event": .object([
                "type": .string("turn/start"),
                "seq": .number(Double(sequence)),
                "time": .number(Double(sequence)),
                "data": .object([:]),
            ]),
        ])
    )
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
