import Foundation
import XCTest

@testable import GlassCore

final class SSEClientTests: XCTestCase {
    func testRecordedStreamReconnectDropsReplayedRPCIDsAndLowSequences() async throws {
        let opener = RecordedSSEOpener(scripts: [
            [
                .frame(Self.sessionEvent(rpcId: "event-1", sequence: 1)),
                .failure(.network("fixture-disconnect")),
            ],
            [
                .frame(Self.sessionEvent(rpcId: "event-1-replay", sequence: 1)),
                .frame(projection(rpcId: "projection-3", sequence: 3)),
                .frame(projection(rpcId: "projection-2-replay", sequence: 2)),
                .frame(Self.sessionEvent(rpcId: "event-2", sequence: 2)),
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

    func testReconnectDropsLateDuplicateUnsequencedHostResponseButKeepsNewResponse() async throws {
        let opener = RecordedSSEOpener(scripts: [
            [
                .frame(settingsDocumentUpdated(rpcId: "settings-revision-1", revision: 1)),
                .failure(.network("fixture-disconnect")),
            ],
            [
                .frame(settingsDocumentUpdated(rpcId: "settings-revision-1", revision: 1)),
                .frame(settingsDocumentUpdated(rpcId: "settings-revision-2", revision: 2)),
            ],
        ])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9241/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        let collector = Task { () throws -> [RPCServerRequest] in
            var frames: [RPCServerRequest] = []
            let stream = await client.reconnectingStream(.host, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
            for try await frame in stream {
                frames.append(frame)
                if frames.count == 2 { return frames }
            }
            return frames
        }

        let frames = try await collector.value

        XCTAssertEqual(frames.map(\.rpcId), ["settings-revision-1", "settings-revision-2"])
        XCTAssertEqual(frames.compactMap { $0.payload.objectValue?["revision"]?.numberValue.map(Int.init) }, [1, 2])
        XCTAssertEqual(opener.openedEndpoints(), [.host, .host])
    }

    func testSequenceFenceDoesNotCrossDeduplicateDifferentSessions() async throws {
        let opener = RecordedSSEOpener(scripts: [[
            .frame(Self.sessionEvent(rpcId: "session-a-seq-1", sequence: 1, sessionID: "fixture-session-a")),
            .frame(Self.sessionEvent(rpcId: "session-b-seq-1", sequence: 1, sessionID: "fixture-session-b")),
        ]])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9237/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        var frames: [RPCServerRequest] = []
        let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
        for try await frame in stream {
            frames.append(frame)
            if frames.count == 2 { break }
        }

        XCTAssertEqual(frames.map(\.rpcId), ["session-a-seq-1", "session-b-seq-1"])
        XCTAssertEqual(frames.map { $0.payload.objectValue?["sessionId"]?.stringValue }, ["fixture-session-a", "fixture-session-b"])
    }

    func testRawReconnectFixtureDropsOutOfOrderSequenceWithoutBlockingNewerFrame() async throws {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = try tryUnwrap(fixture.cases.first(where: { $0.id == "reconnect-duplicate-sequence" }))
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
        for try await frame in stream {
            frames.append(frame)
            if frames.count == 3 { break }
        }

        XCTAssertEqual(frames.map { $0.payload.objectValue?["event"]?.objectValue?["seq"]?.numberValue }, [40, 42, 43])
        XCTAssertEqual(frames.map(\.rpcId), ["fixture-40", "fixture-42", "fixture-43"])
        XCTAssertEqual(opener.openedEndpoints(), [.mux])
    }

    func testRawReconnectFixtureDropsDuplicateSequenceAcrossStreamReopen() async throws {
        let fixture = try OfficialRawEventReplayFixtureCatalog.load()
        let replay = try tryUnwrap(fixture.cases.first(where: { $0.id == "reconnect-duplicate-sequence" }))
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
            RecordedSSEElement.frame(Self.sessionEvent(rpcId: "live-\(sequence)", sequence: sequence))
        }
        script.append(.frame(Self.sessionEvent(rpcId: "late-1000", sequence: 1_000)))
        script.append(.frame(Self.sessionEvent(rpcId: "live-1001", sequence: 1_001)))
        let opener = RecordedSSEOpener(scripts: [script])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9238/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )

        var frames: [RPCServerRequest] = []
        let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
        for try await frame in stream {
            frames.append(frame)
            if frames.count == 1001 { break }
        }

        XCTAssertEqual(frames.count, 1_001)
        XCTAssertEqual(frames.first?.rpcId, "live-1")
        XCTAssertEqual(frames.last?.rpcId, "live-1001")
        XCTAssertFalse(frames.map(\.rpcId).contains("late-1000"))
        XCTAssertEqual(opener.openedEndpoints(), [.mux])
    }

    func testReconnectDiagnosticsStayBoundedAcrossRepeatedNetworkFailures() async throws {
        let scripts = Array(repeating: [RecordedSSEElement.failure(.network("fixture-disconnect"))], count: 81)
        let opener = RecordedSSEOpener(scripts: scripts)
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9240/")!,
            testStreamOpener: { endpoint in opener.open(endpoint) }
        )
        let stream = await client.reconnectingStream(
            .mux,
            policy: .init(initialDelay: 0, maximumDelay: 0, multiplier: 1, maximumReconnectAttempts: 80)
        )

        do {
            for try await _ in stream { XCTFail("failure-only carrier must not deliver a frame") }
            XCTFail("finite repeated failures must exhaust")
        } catch let error {
            XCTAssertTrue(error is DSHTransportError, "expected DSHTransportError, got \(error)")
        }

        let traces = await client.recentReconnectTraces()
        XCTAssertEqual(opener.openedEndpoints().count, 81)
        XCTAssertEqual(traces.count, 100)
        XCTAssertEqual(traces.last?.outcome, .exhausted)
        XCTAssertEqual(traces.last?.attempt, 81)
        XCTAssertEqual(traces.filter { $0.outcome == .opened }.count, 50)
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

    func testConsumerTerminationAfterReconnectCancelsSecondCarrierWithoutThirdOpen() async throws {
        let secondCarrierProduced = expectation(description: "reconnected carrier produces its first frame")
        let secondCarrierCancelled = expectation(description: "reconnected carrier observes consumer cancellation")
        let secondCarrierStopped = expectation(description: "reconnected carrier producer stops")
        let gate = RecoveryGate()
        let opener = RecordedSSEOpener(scripts: [[.failure(.network("fixture-disconnect"))]])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9242/")!,
            testStreamOpener: { endpoint in
                let ignored = opener.open(endpoint)
                if opener.openedEndpoints().count == 1 { return ignored }
                return SSEFrameStream { continuation in
                    let producer = Task {
                        continuation.yield(Self.sessionEvent(rpcId: "reconnected-first", sequence: 1))
                        secondCarrierProduced.fulfill()
                        await gate.wait()
                        if Task.isCancelled { secondCarrierCancelled.fulfill() }
                        secondCarrierStopped.fulfill()
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in producer.cancel() }
                }
            }
        )

        let consumer = Task { () throws -> [RPCServerRequest] in
            let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
            for try await frame in stream { return [frame] }
            return []
        }
        await fulfillment(of: [secondCarrierProduced], timeout: 1)
        let frames = try await consumer.value
        await fulfillment(of: [secondCarrierCancelled, secondCarrierStopped], timeout: 1)
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(frames.map(\.rpcId), ["reconnected-first"])
        XCTAssertEqual(opener.openedEndpoints(), [.mux, .mux])
        let traces = await client.recentReconnectTraces()
        XCTAssertTrue(traces.contains { $0.outcome == .reconnecting && $0.errorCategory == "network" })
        XCTAssertEqual(traces.last?.outcome, .cancelled)
    }

    func testConsumerCancellationBeforeFirstInitialFrameCancelsCarrierWithoutReconnect() async throws {
        let carrierOpened = expectation(description: "initial carrier opens before its first frame")
        let carrierCancelled = expectation(description: "silent initial carrier observes cancellation")
        let carrierStopped = expectation(description: "silent initial carrier producer stops")
        let gate = RecoveryGate()
        let opener = RecordedSSEOpener(scripts: [])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9244/")!,
            testStreamOpener: { endpoint in
                _ = opener.open(endpoint)
                return SSEFrameStream { continuation in
                    let producer = Task {
                        carrierOpened.fulfill()
                        await gate.wait()
                        if Task.isCancelled { carrierCancelled.fulfill() }
                        carrierStopped.fulfill()
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in producer.cancel() }
                }
            }
        )

        let consumer = Task { () throws -> [RPCServerRequest] in
            let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
            var frames: [RPCServerRequest] = []
            for try await frame in stream { frames.append(frame) }
            return frames
        }
        await fulfillment(of: [carrierOpened], timeout: 1)
        consumer.cancel()
        _ = try? await consumer.value
        await fulfillment(of: [carrierCancelled, carrierStopped], timeout: 1)
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(opener.openedEndpoints(), [.mux])
        let traces = await client.recentReconnectTraces()
        XCTAssertEqual(traces.last?.outcome, .cancelled)
    }

    func testConsumerCancellationBeforeFirstReconnectedFrameCancelsSecondCarrierWithoutThirdOpen() async throws {
        let secondCarrierOpened = expectation(description: "reconnected carrier opens before its first frame")
        let secondCarrierCancelled = expectation(description: "silent reconnected carrier observes cancellation")
        let secondCarrierStopped = expectation(description: "silent reconnected carrier producer stops")
        let gate = RecoveryGate()
        let opener = RecordedSSEOpener(scripts: [[.failure(.network("fixture-disconnect"))]])
        let client = SSEClient(
            baseURL: URL(string: "http://127.0.0.1:9243/")!,
            testStreamOpener: { endpoint in
                let ignored = opener.open(endpoint)
                if opener.openedEndpoints().count == 1 { return ignored }
                return SSEFrameStream { continuation in
                    let producer = Task {
                        secondCarrierOpened.fulfill()
                        await gate.wait()
                        if Task.isCancelled { secondCarrierCancelled.fulfill() }
                        secondCarrierStopped.fulfill()
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in producer.cancel() }
                }
            }
        )

        let consumer = Task { () throws -> [RPCServerRequest] in
            let stream = await client.reconnectingStream(.mux, policy: .init(initialDelay: 0.01, maximumDelay: 0.02, multiplier: 2))
            var frames: [RPCServerRequest] = []
            for try await frame in stream { frames.append(frame) }
            return frames
        }
        await fulfillment(of: [secondCarrierOpened], timeout: 1)
        consumer.cancel()
        _ = try? await consumer.value
        await fulfillment(of: [secondCarrierCancelled, secondCarrierStopped], timeout: 1)
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(opener.openedEndpoints(), [.mux, .mux])
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

        let wire = try JSONEncoder().encode(Self.sessionEvent(rpcId: "valid", sequence: 8))
        XCTAssertNil(parser.consume(line: "data: " + String(decoding: wire, as: UTF8.self)))
        let valid = parser.consume(line: "")
        XCTAssertEqual(valid?.type, "server-request")
        XCTAssertEqual(valid?.rpcId, "valid")
        XCTAssertEqual(valid?.method, "session/event")
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try XCTUnwrap(value, "Expected non-nil value", file: file, line: line)
    }

    private static func sessionEvent(rpcId: String, sequence: Int, sessionID: String = "fixture-session") -> RPCServerRequest {
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

    private func settingsDocumentUpdated(rpcId: String, revision: Int) -> RPCServerRequest {
        RPCServerRequest(
            type: "server-request",
            rpcId: rpcId,
            method: "settings/document-updated",
            payload: .object([
                "type": .string("settings/document-updated"),
                "namespace": .string("fixture-settings"),
                "revision": .number(Double(revision)),
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
