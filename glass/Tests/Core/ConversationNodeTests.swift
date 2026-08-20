import XCTest

@testable import GlassCore

final class ConversationNodeTests: XCTestCase {
    func testStableContextKeyUsesKindLengthInsteadOfAmbiguousDelimiter() {
        XCTAssertEqual(conversationContextKey(kind: "turn", id: "alpha"), "4:turnalpha")
        XCTAssertNotEqual(
            conversationContextKey(kind: "a:b", id: "c"),
            conversationContextKey(kind: "a", id: "b:c")
        )
        XCTAssertEqual(conversationContextKey(kind: "用户", id: "会话"), "6:用户会话")
    }

    func testTypeErasedDefinitionPreservesMatchLifecyclePublicationAndViewTarget() {
        let erased = AnyConversationNodeDefinition(FixtureDefinition())
        let startEvent = event(seq: 10, type: "fixture/start")
        let updateEvent = event(seq: 11, type: "fixture/update")
        let startInput = ConversationEventInput(event: startEvent)
        let updateInput = ConversationEventInput(event: updateEvent)
        let startMatch = ConversationMatch(input: startInput, role: .start, location: .session)
        let updateMatch = ConversationMatch(input: updateInput, role: .update, location: .session)
        let key = conversationContextKey(kind: erased.kind, id: "work")

        XCTAssertEqual(erased.kind, "fixture")
        XCTAssertEqual(erased.target, "chat")
        XCTAssertEqual(erased.match(startEvent), ConversationMatchResult(id: "work", role: .start))
        XCTAssertEqual(erased.match(updateEvent), ConversationMatchResult(id: "work", role: .update))
        XCTAssertNil(erased.match(event(seq: 12, type: "other")))
        XCTAssertEqual(erased.publication(for: startMatch), .animationFrame)
        XCTAssertEqual(erased.publication(for: updateMatch), .immediate)

        let initial = ConversationNodeContext<Any>(
            key: key,
            kind: erased.kind,
            id: "work",
            matches: [startMatch],
            start: startMatch,
            state: nil,
            current: [:]
        )
        let started = erased.start(context: initial, match: startMatch, reader: EmptyReader())
        XCTAssertEqual(started as? FixtureDefinition.State, .init(text: "start", revisions: 0))

        let updating = ConversationNodeContext<Any>(
            key: key,
            kind: erased.kind,
            id: "work",
            matches: [startMatch, updateMatch],
            start: startMatch,
            state: started,
            current: [:]
        )
        let updated = erased.update(context: updating, match: updateMatch)
        XCTAssertEqual(updated as? FixtureDefinition.State, .init(text: "start+update", revisions: 1))
        let node = erased.buildViewNode(context: .init(
            key: key,
            kind: erased.kind,
            id: "work",
            matches: [startMatch, updateMatch],
            start: startMatch,
            state: updated,
            current: [:]
        ))
        XCTAssertEqual(node?.key, key)
        XCTAssertEqual(node?.kind, "fixture")
        XCTAssertEqual(node?.id, "work")
        XCTAssertEqual(node?.target, "chat")
        XCTAssertEqual((node?.data as? FixtureDefinition.State)?.revisions, 1)
    }

    func testReducerIsTheOnlyLifecycleOwnerAndMaterializesStableTargetNodes() {
        let reducer = ConversationNodeReducer(definitions: [.init(FixtureDefinition())])
        let start = ConversationEventInput(event: event(seq: 30, type: "fixture/start", data: ["turn": .number(4), "step": .number(1)]))
        let update = ConversationEventInput(event: event(seq: 31, type: "fixture/update", data: ["turn": .number(4), "step": .number(1)]))

        XCTAssertEqual(reducer.replaceWindow([start], hasMore: false), .immediate)
        var chat = reducer.snapshot(target: "chat")
        XCTAssertEqual(chat.count, 1)
        XCTAssertEqual((chat[0].data as? FixtureDefinition.State)?.revisions, 0)
        XCTAssertEqual(chat[0].key, conversationContextKey(kind: "fixture", id: "work"))

        XCTAssertEqual(reducer.append(update), .immediate)
        chat = reducer.snapshot(target: "chat")
        XCTAssertEqual(chat.count, 1, "a streaming/update lifecycle upserts its stable context node rather than duplicating a row")
        XCTAssertEqual((chat[0].data as? FixtureDefinition.State)?.revisions, 1)
        XCTAssertEqual(reducer.rawWindow().map(\.event.seq), [30, 31])
    }

    func testLocationVisibilityAndLocationDataRemainExplicitReducerValues() {
        let event = event(seq: 20, type: "turn/start")
        let stepStore = ConversationLocationDataStore(values: ["progress": 0.5])
        let turn = ConversationTurnLocation(
            turn: 3,
            start: event,
            end: nil,
            status: .open,
            steps: [],
            data: .init(values: ["workspace": "fixture"])
        )
        let step = ConversationStepLocation(
            turn: 3,
            step: 2,
            start: event,
            end: nil,
            status: .open,
            data: stepStore
        )
        let location = ConversationLocation.step(turn: turn, step: step)
        let view = ChatConversationViewNode(
            key: "7:fixtureid",
            kind: "fixture",
            id: "id",
            data: "payload",
            anchorSeq: 20,
            location: location,
            visibility: .hidden
        )

        XCTAssertEqual(view.node.target, "chat")
        XCTAssertEqual(view.anchorSeq, 20)
        XCTAssertEqual(view.visibility, .hidden)
        XCTAssertEqual(stepStore.value(for: "progress", as: Double.self), 0.5)
        XCTAssertEqual(turn.data.value(for: "workspace", as: String.self), "fixture")
        guard case let .step(resolvedTurn, resolvedStep) = view.location else {
            return XCTFail("chat nodes retain their engine-owned turn/step location")
        }
        XCTAssertEqual(resolvedTurn.turn, 3)
        XCTAssertEqual(resolvedStep.step, 2)
    }

    func testReducerResolvesEngineOwnedTurnAndStepLocationDuringWindowReplay() {
        let reducer = ConversationNodeReducer(definitions: [.init(LocationFixtureDefinition())])
        let entries = [
            ConversationEventInput(event: event(seq: 1, type: "turn/start", data: ["turn": .number(3)])),
            ConversationEventInput(event: event(seq: 2, type: "step/start", data: ["turn": .number(3), "step": .number(2)])),
            ConversationEventInput(event: event(seq: 3, type: "fixture/location", data: ["turn": .number(3), "step": .number(2)])),
            ConversationEventInput(event: event(seq: 4, type: "step/end", data: ["turn": .number(3), "step": .number(2)])),
            ConversationEventInput(event: event(seq: 5, type: "turn/end", data: ["turn": .number(3)])),
        ]

        XCTAssertEqual(reducer.replaceWindow(entries, hasMore: false), .immediate)
        guard let state = reducer.snapshot(target: "chat").first?.data as? LocationFixtureDefinition.State else {
            return XCTFail("location fixture must materialize a typed chat node")
        }
        XCTAssertEqual(state.turn, 3)
        XCTAssertEqual(state.step, 2)
        XCTAssertEqual(state.turnStatus, "closed")
        XCTAssertEqual(state.stepStatus, "closed")
        XCTAssertEqual(reducer.rawWindow().map(\.event.seq), [1, 2, 3, 4, 5])
    }

    func testReducerReturnsGreatestPublicationAcrossDefinitionsForOneEvent() {
        let reducer = ConversationNodeReducer(definitions: [
            .init(PublicationFixtureDefinition(kind: "fixture-frame", target: "chat", publication: .animationFrame)),
            .init(PublicationFixtureDefinition(kind: "fixture-immediate", target: "inspector", publication: .immediate)),
        ])
        let input = ConversationEventInput(event: event(seq: 40, type: "fixture/publication"))

        XCTAssertEqual(reducer.append(input), .immediate)
        XCTAssertEqual(reducer.snapshot(target: "chat").count, 1)
        XCTAssertEqual(reducer.snapshot(target: "inspector").count, 1)
        XCTAssertEqual(reducer.rawWindow().map(\.event.seq), [40])
    }

    /// Differential guard for the incremental streaming path: appending the same
    /// window one event at a time must produce byte-for-byte the same raw
    /// window, view-node array (keys/order/payloads), and location facts that a
    /// single full rebuild produces — including facts an update retires.
    func testIncrementalAppendsMatchFullRebuildSnapshot() {
        let definitions: [AnyConversationNodeDefinition] = [
            .init(FixtureDefinition()),
            .init(LocationFixtureDefinition()),
            .init(ChurnFixtureDefinition()),
        ]
        let events: [ConversationEventInput] = [
            .init(event: event(seq: 1, type: "turn/start", data: ["turn": .number(1)])),
            .init(event: event(seq: 2, type: "step/start", data: ["turn": .number(1), "step": .number(1)])),
            .init(event: event(seq: 3, type: "fixture/start", data: ["turn": .number(1), "step": .number(1)])),
            .init(event: event(seq: 4, type: "fixture/update", data: ["turn": .number(1), "step": .number(1)])),
            .init(event: event(seq: 5, type: "fixture/location", data: ["turn": .number(1), "step": .number(1)])),
            .init(event: event(seq: 6, type: "churn/start", data: ["turn": .number(1), "step": .number(1)])),
            .init(event: event(seq: 7, type: "churn/finish", data: ["turn": .number(1), "step": .number(1)])),
            .init(event: event(seq: 8, type: "step/end", data: ["turn": .number(1), "step": .number(1)])),
            .init(event: event(seq: 9, type: "turn/end", data: ["turn": .number(1)])),
            .init(event: event(seq: 10, type: "fixture/publication", data: [:])),
        ]

        let full = ConversationNodeReducer(definitions: definitions)
        full.replaceWindow(events, hasMore: false)

        let incremental = ConversationNodeReducer(definitions: definitions)
        for input in events {
            incremental.append(input)
        }

        XCTAssertEqual(incremental.rawWindow().map(\.event.seq), full.rawWindow().map(\.event.seq))
        for target in ["chat", "inspector", "timeline"] {
            assertNodesEqual(incremental.snapshot(target: target), full.snapshot(target: target))
        }
        for turn in 0...2 {
            assertLocationEqual(
                incremental.locationData(scope: .turn, turn: turn),
                full.locationData(scope: .turn, turn: turn)
            )
            for step in [nil, 1, 2] {
                assertLocationEqual(
                    incremental.locationData(scope: .step, turn: turn, step: step),
                    full.locationData(scope: .step, turn: turn, step: step)
                )
            }
        }
    }

    private func assertNodesEqual(
        _ lhs: [ConversationViewNode],
        _ rhs: [ConversationViewNode],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.map(\.key), rhs.map(\.key), "view node keys diverge", file: file, line: line)
        XCTAssertEqual(lhs.map(\.kind), rhs.map(\.kind), "view node kinds diverge", file: file, line: line)
        XCTAssertEqual(lhs.map(\.id), rhs.map(\.id), "view node ids diverge", file: file, line: line)
        XCTAssertEqual(lhs.map(\.target), rhs.map(\.target), "view node targets diverge", file: file, line: line)
        XCTAssertEqual(
            lhs.map { String(describing: $0.data) },
            rhs.map { String(describing: $0.data) },
            "view node payloads diverge",
            file: file,
            line: line
        )
    }

    private func assertLocationEqual(
        _ lhs: ConversationLocationDataStore,
        _ rhs: ConversationLocationDataStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            lhs.value(for: "churnDone", as: String.self),
            rhs.value(for: "churnDone", as: String.self),
            "churn location fact diverges",
            file: file,
            line: line
        )
    }

    private struct ChurnFixtureDefinition: ConversationNodeDefinition {
        struct State: Equatable {
            let seqStart: Int
            let phase: String
        }

        let kind = "churn"
        let target: String? = "inspector"

        func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
            switch event.type {
            case "churn/start": return .init(id: "churn", role: .start)
            case "churn/finish": return .init(id: "churn", role: .update)
            default: return nil
            }
        }

        func start(
            context _: ConversationNodeContext<State>,
            match: ConversationMatch,
            reader _: any ConversationContextReader
        ) -> State {
            .init(seqStart: match.event.seq, phase: "open")
        }

        func update(context: ConversationNodeContext<State>, match _: ConversationMatch) -> State {
            guard let state = context.state else { preconditionFailure("churn update requires state") }
            return .init(seqStart: state.seqStart, phase: "done")
        }

        func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
            guard let state = context.state, let target else { return nil }
            return .init(key: context.key, kind: context.kind, id: context.id, target: target, data: state)
        }

        /// Retires the fact after `.open` and issues a fresh `turn`-scoped fact
        /// only once the update lands. An incremental append must remove the
        /// stale key exactly like a full rebuild would.
        func buildLocationData(
            context: ConversationNodeContext<State>,
            scope: ConversationLocationData.Scope
        ) -> ConversationLocationData? {
            guard let state = context.state, state.phase == "done", scope == .turn,
                  let turn = turnNumber(of: context.matches.last?.location ?? .unresolved)
            else { return nil }
            return .init(scope: scope, turn: turn, step: nil, key: "churnDone", value: state.phase)
        }

        private func turnNumber(of location: ConversationLocation) -> Int? {
            switch location {
            case .session, .unresolved: return nil
            case .turn(let turn): return turn.turn
            case .step(let turn, _): return turn.turn
            }
        }
    }

    private func event(seq: Int, type: String, data: [String: JSONValue] = [:]) -> SessionEventDTO {
        SessionEventDTO(
            type: type,
            seq: seq,
            time: Double(seq),
            data: .object(["fixture": .string(type)].merging(data) { _, right in right }),
            sourceEventSeqs: nil,
            ignorable: nil
        )
    }

    private struct EmptyReader: ConversationContextReader {
        func previous<State>(kind _: String, as _: State.Type) -> ConversationPreviousContext<State>? { nil }
    }

    private struct FixtureDefinition: ConversationNodeDefinition {
        struct State: Equatable {
            let text: String
            let revisions: Int
        }

        let kind = "fixture"
        let target: String? = "chat"

        func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
            switch event.type {
            case "fixture/start": return .init(id: "work", role: .start)
            case "fixture/update": return .init(id: "work", role: .update)
            default: return nil
            }
        }

        func start(
            context _: ConversationNodeContext<State>,
            match _: ConversationMatch,
            reader _: any ConversationContextReader
        ) -> State {
            .init(text: "start", revisions: 0)
        }

        func update(context: ConversationNodeContext<State>, match _: ConversationMatch) -> State {
            .init(text: context.state?.text.appending("+update") ?? "invalid", revisions: (context.state?.revisions ?? -1) + 1)
        }

        func publication(for match: ConversationMatch) -> ConversationPublication {
            match.role == .start ? .animationFrame : .immediate
        }

        func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
            guard let state = context.state else { return nil }
            return .init(key: context.key, kind: context.kind, id: context.id, target: "chat", data: state)
        }
    }

    private struct LocationFixtureDefinition: ConversationNodeDefinition {
        struct State: Equatable {
            let turn: Int
            let step: Int
            let turnStatus: String
            let stepStatus: String
        }

        let kind = "fixture-location"
        let target: String? = "chat"

        func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
            event.type == "fixture/location" ? .init(id: "location", role: .start) : nil
        }

        func start(
            context _: ConversationNodeContext<State>,
            match: ConversationMatch,
            reader _: any ConversationContextReader
        ) -> State {
            guard case let .step(turn, step) = match.location else {
                preconditionFailure("fixture/location requires an engine-owned step location")
            }
            return .init(
                turn: turn.turn,
                step: step.step,
                turnStatus: turn.status.rawValue,
                stepStatus: step.status.rawValue
            )
        }

        func update(context: ConversationNodeContext<State>, match _: ConversationMatch) -> State {
            guard let state = context.state else { preconditionFailure("location update requires state") }
            return state
        }

        func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
            guard let state = context.state else { return nil }
            return .init(key: context.key, kind: context.kind, id: context.id, target: "chat", data: state)
        }
    }

    private struct PublicationFixtureDefinition: ConversationNodeDefinition {
        struct State: Equatable { let seq: Int }

        let kind: String
        let target: String?
        let publicationValue: ConversationPublication

        init(kind: String, target: String, publication: ConversationPublication) {
            self.kind = kind
            self.target = target
            self.publicationValue = publication
        }

        func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
            event.type == "fixture/publication" ? .init(id: "publication", role: .start) : nil
        }

        func start(
            context _: ConversationNodeContext<State>,
            match: ConversationMatch,
            reader _: any ConversationContextReader
        ) -> State {
            .init(seq: match.event.seq)
        }

        func update(context: ConversationNodeContext<State>, match _: ConversationMatch) -> State {
            guard let state = context.state else { preconditionFailure("publication update requires state") }
            return state
        }

        func publication(for _: ConversationMatch) -> ConversationPublication { publicationValue }

        func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
            guard let state = context.state, let target else { return nil }
            return .init(key: context.key, kind: context.kind, id: context.id, target: target, data: state)
        }
    }
}
