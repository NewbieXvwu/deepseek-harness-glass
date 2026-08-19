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

    private func event(seq: Int, type: String) -> SessionEventDTO {
        SessionEventDTO(
            type: type,
            seq: seq,
            time: Double(seq),
            data: .object(["fixture": .string(type)]),
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
}
