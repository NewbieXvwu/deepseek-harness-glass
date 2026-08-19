import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Session-owned reducer for one ordered raw history window. It is deliberately
/// the only Core surface that invokes `ConversationNodeDefinition.match`,
/// `start`, `update`, or `buildViewNode`; target renderers only read its already
/// materialized `ConversationViewNode` snapshots.
final class ConversationNodeReducer {
    final class Context {
        let definition: AnyConversationNodeDefinition
        let key: String
        let kind: String
        let id: String
        var start: ConversationMatch?
        var state: Any?
        var matches: [ConversationMatch] = []
        var current: [String: ConversationViewNode?] = [:]

        init(definition: AnyConversationNodeDefinition, id: String) {
            self.definition = definition
            self.kind = definition.kind
            self.id = id
            self.key = conversationContextKey(kind: definition.kind, id: id)
        }

        var startSeq: Int? { start?.event.seq }

        func snapshot() -> ConversationNodeContext<Any> {
            ConversationNodeContext(
                key: key,
                kind: kind,
                id: id,
                matches: matches,
                start: start,
                state: state,
                current: current
            )
        }
    }

    private let definitions: [AnyConversationNodeDefinition]
    private let fallback: AnyConversationNodeDefinition?
    private var inputsBySeq: [Int: ConversationEventInput] = [:]
    private var contexts: [String: Context] = [:]
    private var hasMoreHistory = false
    private var nodesByTarget: [String: [ConversationViewNode]] = [:]

    init(
        definitions: [AnyConversationNodeDefinition],
        fallback: AnyConversationNodeDefinition? = nil
    ) {
        precondition(Set(definitions.map(\.kind)).count == definitions.count, "conversation Definition kinds must be unique")
        self.definitions = definitions
        self.fallback = fallback
    }

    /// Replaces a complete contiguous authority window after open, resync, or
    /// gap repair. Entries must be strictly ordered; sorting corrupt input would
    /// hide a broken Host/page contract and is therefore forbidden.
    @discardableResult
    func replaceWindow(
        _ entries: [ConversationEventInput],
        hasMore: Bool
    ) -> ConversationPublication {
        try! assertStrictAscending(entries)
        inputsBySeq = Dictionary(uniqueKeysWithValues: entries.map { ($0.event.seq, $0) })
        hasMoreHistory = hasMore
        rebuild()
        return .immediate
    }

    /// Appends one verified live tail event. Duplicate deliveries are idempotent;
    /// a gap or stale nonduplicate event is a pager/reconnect repair condition.
    @discardableResult
    func append(_ input: ConversationEventInput) -> ConversationPublication {
        let seq = input.event.seq
        if inputsBySeq[seq] != nil { return .none }
        if let tail = inputsBySeq.keys.max(), seq <= tail {
            preconditionFailure("conversation reducer received non-appended live seq \(seq) after \(tail)")
        }
        inputsBySeq[seq] = input
        rebuild()
        return publication(for: input)
    }

    /// Prepends verified older history without accepting a duplicate or a page
    /// that overlaps the current first raw sequence. Pager continuity validation
    /// remains authoritative; this boundary makes a reducer violation explicit.
    @discardableResult
    func prepend(
        _ entries: [ConversationEventInput],
        hasMore: Bool
    ) -> ConversationPublication {
        try! assertStrictAscending(entries)
        if let first = inputsBySeq.keys.min(), let lastIncoming = entries.last?.event.seq {
            precondition(lastIncoming < first, "conversation reducer older page overlaps current raw window")
        }
        for entry in entries {
            precondition(inputsBySeq[entry.event.seq] == nil, "conversation reducer received duplicate prepended seq")
            inputsBySeq[entry.event.seq] = entry
        }
        hasMoreHistory = hasMore
        rebuild()
        return entries.reduce(.immediate) { ConversationPublication.maximum($0, publication(for: $1)) }
    }

    func snapshot(target: String) -> [ConversationViewNode] {
        nodesByTarget[target] ?? []
    }

    func rawWindow() -> [ConversationEventInput] {
        sortedInputs()
    }

    func currentHasMoreHistory() -> Bool { hasMoreHistory }

    private func rebuild() {
        contexts.removeAll(keepingCapacity: true)
        nodesByTarget.removeAll(keepingCapacity: true)
        let timeline = ConversationTimeline(entries: sortedInputs())
        for input in sortedInputs() {
            accept(input, timeline: timeline)
        }
        materialize()
    }

    private func accept(_ input: ConversationEventInput, timeline: ConversationTimeline) {
        var matchedTargets = Set<String>()
        for definition in definitions {
            guard let result = definition.match(input.event) else { continue }
            if let target = definition.target { matchedTargets.insert(target) }
            accept(definition: definition, result: result, input: input, timeline: timeline)
        }
        if let fallback, let target = fallback.target, !matchedTargets.contains(target), let result = fallback.match(input.event) {
            accept(definition: fallback, result: result, input: input, timeline: timeline)
        }
    }

    private func accept(
        definition: AnyConversationNodeDefinition,
        result: ConversationMatchResult,
        input: ConversationEventInput,
        timeline: ConversationTimeline
    ) {
        let key = conversationContextKey(kind: definition.kind, id: result.id)
        let context: Context
        if let existing = contexts[key] {
            precondition(existing.definition.kind == definition.kind && existing.id == result.id,
                         "conversation reducer context identity changed definition")
            context = existing
        } else {
            context = Context(definition: definition, id: result.id)
            contexts[key] = context
        }
        let match = ConversationMatch(input: input, role: result.role, location: timeline.location(for: input.event))
        if let previous = context.matches.last {
            precondition(previous.event.seq < match.event.seq,
                         "conversation reducer received non-monotonic context evidence for \(context.key)")
        }
        if result.role == .start {
            precondition(context.start == nil, "conversation reducer received a duplicate start for \(context.key)")
            precondition(context.matches.isEmpty, "conversation reducer received an update before start for \(context.key)")
            context.start = match
            context.matches.append(match)
            context.state = definition.start(context: context.snapshot(), match: match, reader: reader(before: match.event.seq))
        } else {
            context.matches.append(match)
            if context.state != nil {
                context.state = definition.update(context: context.snapshot(), match: match)
            }
        }
    }

    private func materialize() {
        var next: [String: [ConversationViewNode]] = [:]
        let ordered = contexts.values.sorted { lhs, rhs in
            let left = lhs.startSeq ?? lhs.matches.first?.event.seq ?? Int.max
            let right = rhs.startSeq ?? rhs.matches.first?.event.seq ?? Int.max
            if left == right { return lhs.key < rhs.key }
            return left < right
        }
        for context in ordered {
            guard let target = context.definition.target else { continue }
            guard let node = context.definition.buildViewNode(context: context.snapshot()) else { continue }
            precondition(node.key == context.key,
                         "conversation Definition \(context.kind) produced unstable key \(node.key), expected \(context.key)")
            precondition(node.target == target,
                         "conversation Definition \(context.kind) produced \(node.target), expected \(target)")
            context.current[target] = node
            next[target, default: []].append(node)
        }
        for target in next.keys {
            guard target == "chat" else { continue }
            next[target]?.sort { left, right in
                let leftAnchor = left.anchorSeq ?? .greatestFiniteMagnitude
                let rightAnchor = right.anchorSeq ?? .greatestFiniteMagnitude
                if leftAnchor == rightAnchor { return left.key < right.key }
                return leftAnchor < rightAnchor
            }
        }
        nodesByTarget = next
    }

    private func publication(for input: ConversationEventInput) -> ConversationPublication {
        var result: ConversationPublication = .none
        var matchedTargets = Set<String>()
        for definition in definitions {
            guard let matchResult = definition.match(input.event) else { continue }
            if let target = definition.target { matchedTargets.insert(target) }
            let match = ConversationMatch(input: input, role: matchResult.role, location: .unresolved)
            result = ConversationPublication.maximum(result, definition.publication(for: match))
        }
        if let fallback, let target = fallback.target, !matchedTargets.contains(target), let matchResult = fallback.match(input.event) {
            result = ConversationPublication.maximum(
                result,
                fallback.publication(for: .init(input: input, role: matchResult.role, location: .unresolved))
            )
        }
        return result
    }

    private func reader(before seq: Int) -> any ConversationContextReader {
        ReducerPreviousReader(contexts: contexts.values, before: seq, hasMore: hasMoreHistory)
    }

    private func sortedInputs() -> [ConversationEventInput] {
        inputsBySeq.keys.sorted().compactMap { inputsBySeq[$0] }
    }

    private func assertStrictAscending(_ entries: [ConversationEventInput]) throws {
        for pair in zip(entries, entries.dropFirst()) {
            guard pair.0.event.seq < pair.1.event.seq else {
                throw ConversationReducerError.nonAscendingWindow(previous: pair.0.event.seq, current: pair.1.event.seq)
            }
        }
    }
}

private enum ConversationReducerError: Error, Equatable {
    case nonAscendingWindow(previous: Int, current: Int)
}

/// Dependency reader backed by immutable snapshots of contexts already reduced
/// before the current start evidence. Absence is intentionally distinct from a
/// Host history gap; definitions can decide how to degrade from either state.
private struct ReducerPreviousReader: ConversationContextReader {
    private struct Candidate {
        let key: String
        let kind: String
        let id: String
        let startSeq: Int
        let state: Any
        let matches: [ConversationMatch]
    }

    private let candidates: [Candidate]
    private let before: Int
    let hasMore: Bool

    init(contexts: Dictionary<String, ConversationNodeReducer.Context>.Values, before: Int, hasMore: Bool) {
        self.before = before
        self.hasMore = hasMore
        candidates = contexts.compactMap { context in
            guard let startSeq = context.startSeq, let state = context.state else { return nil }
            return Candidate(
                key: context.key,
                kind: context.kind,
                id: context.id,
                startSeq: startSeq,
                state: state,
                matches: context.matches
            )
        }.sorted { $0.startSeq < $1.startSeq }
    }

    func previous<State>(kind: String, as: State.Type) -> ConversationPreviousContext<State>? {
        guard let candidate = candidates.last(where: { $0.kind == kind && $0.startSeq < before }),
              let state = candidate.state as? State
        else { return nil }
        return ConversationPreviousContext(
            key: candidate.key,
            kind: candidate.kind,
            id: candidate.id,
            startSeq: candidate.startSeq,
            state: state,
            matches: candidate.matches
        )
    }
}

/// Minimal engine-owned location index over the complete raw history window.
/// It preserves official session/turn/step status facts before Definitions see
/// evidence and is rebuilt whenever authority history changes.
private struct ConversationTimeline {
    private struct StepFacts {
        var start: SessionEventDTO?
        var end: SessionEventDTO?
    }
    private struct TurnFacts {
        var start: SessionEventDTO?
        var end: SessionEventDTO?
        var steps: [Int: StepFacts]
    }

    private var turns: [Int: TurnFacts] = [:]

    init(entries: [ConversationEventInput]) {
        for entry in entries {
            let event = entry.event
            guard let turn = event.data.integer(named: "turn") else { continue }
            var facts = turns[turn] ?? TurnFacts(start: nil, end: nil, steps: [:])
            if event.type == "turn/start" { facts.start = event }
            if event.type == "turn/end" { facts.end = event }
            if let step = event.data.integer(named: "step") {
                var stepFacts = facts.steps[step] ?? StepFacts(start: nil, end: nil)
                if event.type == "step/start" { stepFacts.start = event }
                if event.type == "step/end" { stepFacts.end = event }
                facts.steps[step] = stepFacts
            }
            turns[turn] = facts
        }
    }

    func location(for event: SessionEventDTO) -> ConversationLocation {
        guard let turnNumber = event.data.integer(named: "turn"), let facts = turns[turnNumber] else {
            return .session
        }
        let turn = makeTurn(number: turnNumber, facts: facts)
        guard let stepNumber = event.data.integer(named: "step") else { return .turn(turn) }
        let stepFacts = facts.steps[stepNumber] ?? StepFacts(start: nil, end: nil)
        let step = ConversationStepLocation(
            turn: turnNumber,
            step: stepNumber,
            start: stepFacts.start,
            end: stepFacts.end,
            status: stepStatus(start: stepFacts.start, end: stepFacts.end),
            data: .init()
        )
        return .step(turn: turn, step: step)
    }

    private func makeTurn(number: Int, facts: TurnFacts) -> ConversationTurnLocation {
        let steps = facts.steps.keys.sorted().map { stepNumber -> ConversationStepLocation in
            let step = facts.steps[stepNumber] ?? StepFacts(start: nil, end: nil)
            return ConversationStepLocation(
                turn: number,
                step: stepNumber,
                start: step.start,
                end: step.end,
                status: stepStatus(start: step.start, end: step.end),
                data: .init()
            )
        }
        return ConversationTurnLocation(
            turn: number,
            start: facts.start,
            end: facts.end,
            status: turnStatus(start: facts.start, end: facts.end),
            steps: steps,
            data: .init()
        )
    }

    private func turnStatus(start: SessionEventDTO?, end: SessionEventDTO?) -> ConversationTurnLocation.Status {
        if start != nil && end == nil { return .open }
        if end != nil { return .closed }
        return .unknown
    }

    private func stepStatus(start: SessionEventDTO?, end: SessionEventDTO?) -> ConversationStepLocation.Status {
        if start != nil && end == nil { return .open }
        if end != nil { return .closed }
        return .unknown
    }
}

private extension JSONValue {
    func integer(named key: String) -> Int? {
        guard let number = objectValue?[key]?.numberValue,
              number.rounded(.towardZero) == number,
              number >= 0,
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}
