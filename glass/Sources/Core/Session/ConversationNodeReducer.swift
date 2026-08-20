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
        /// Engine-issued `locationDataByKey` keys for this context, tracked so an
        /// incremental append can retire facts that an update invalidates.
        var locationKeys: Set<String> = []

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
    private var locationDataByKey: [String: ConversationLocationData] = [:]
    /// Highest resident raw sequence. Kept as an O(1) append guard so a 10k
    /// streaming chunk run never rescans the dictionary per event.
    private var latestSeq: Int?
    /// Engine-owned location index over the resident raw window. Live `append`
    /// events extend it incrementally instead of rescanning the whole window,
    /// which keeps streaming cost linear in the number of chunks.
    private var timeline = ConversationTimeline(entries: [])

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
    /// Appends are incremental: only the accepted event's contexts are accepted
    /// and re-materialized instead of replaying the whole raw window, which keeps
    /// the streaming path O(1) per event instead of O(n).
    @discardableResult
    func append(_ input: ConversationEventInput) -> ConversationPublication {
        let seq = input.event.seq
        if inputsBySeq[seq] != nil { return .none }
        if let tail = latestSeq, seq <= tail {
            preconditionFailure("conversation reducer received non-appended live seq \(seq) after \(tail)")
        }
        inputsBySeq[seq] = input
        latestSeq = seq
        timeline.append(input)
        if input.event.affectsLocationFacts {
            // Boundary evidence changes engine-owned turn/step facts. Definitions
            // that derive node data or location data from those facts must all be
            // replayed, exactly like the full-window rebuild path, so a streaming
            // reader never sees a stale status. Boundary events are a small
            // fraction of a live stream, so the amortized cost stays linear.
            rebuild()
        } else {
            let affected = accept(input, timeline: timeline)
            materializeAppended(affected)
        }
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

    /// Engine-materialized state-only node values for one exact turn/step.
    /// Target renderers receive typed results through their Store adapters and
    /// never reconstruct them by reparsing raw Host events.
    func locationData(
        scope: ConversationLocationData.Scope,
        turn: Int,
        step: Int? = nil
    ) -> ConversationLocationDataStore {
        var values: [String: Any] = [:]
        for data in locationDataByKey.values where data.scope == scope
            && data.turn == turn && data.step == step {
            values[data.key] = data.value
        }
        return .init(values: values)
    }

    func currentHasMoreHistory() -> Bool { hasMoreHistory }

    private func rebuild() {
        contexts.removeAll(keepingCapacity: true)
        nodesByTarget.removeAll(keepingCapacity: true)
        latestSeq = inputsBySeq.keys.max()
        timeline = ConversationTimeline(entries: sortedInputs())
        for input in sortedInputs() {
            _ = accept(input, timeline: timeline)
        }
        materialize()
    }

    private func accept(_ input: ConversationEventInput, timeline: ConversationTimeline) -> Set<String> {
        var matchedTargets = Set<String>()
        var affected = Set<String>()
        for definition in definitions {
            guard let result = definition.match(input.event) else { continue }
            if let target = definition.target { matchedTargets.insert(target) }
            affected.insert(accept(definition: definition, result: result, input: input, timeline: timeline))
        }
        if let fallback, let target = fallback.target, !matchedTargets.contains(target), let result = fallback.match(input.event) {
            affected.insert(accept(definition: fallback, result: result, input: input, timeline: timeline))
        }
        return affected
    }

    private func accept(
        definition: AnyConversationNodeDefinition,
        result: ConversationMatchResult,
        input: ConversationEventInput,
        timeline: ConversationTimeline
    ) -> String {
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
        return key
    }

    private func materialize() {
        var next: [String: [ConversationViewNode]] = [:]
        var locationData: [String: ConversationLocationData] = [:]
        let ordered = contexts.values.sorted { lhs, rhs in
            let left = lhs.startSeq ?? lhs.matches.first?.event.seq ?? Int.max
            let right = rhs.startSeq ?? rhs.matches.first?.event.seq ?? Int.max
            if left == right { return lhs.key < rhs.key }
            return left < right
        }
        for context in ordered {
            let snapshot = context.snapshot()
            for scope in [ConversationLocationData.Scope.turn, .step] {
                guard let data = context.definition.buildLocationData(context: snapshot, scope: scope) else { continue }
                locationData[locationDataKey(data)] = data
            }
            guard let target = context.definition.target else { continue }
            guard let node = context.definition.buildViewNode(context: snapshot) else { continue }
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
        for context in contexts.values {
            context.locationKeys = Set([ConversationLocationData.Scope.turn, .step].compactMap { scope in
                guard let data = context.definition.buildLocationData(context: context.snapshot(), scope: scope) else { return nil }
                return locationDataKey(data)
            })
        }
        nodesByTarget = next
        locationDataByKey = locationData
    }

    /// Incremental counterpart of `materialize()` for one live append. Only the
    /// contexts the event touched are re-materialized: location facts that an
    /// update invalidated are retired, and view nodes are replaced in place with
    /// chat anchored into the same sorted order a full rebuild would produce.
    private func materializeAppended(_ affected: Set<String>) {
        for key in affected {
            guard let context = contexts[key] else { continue }
            let snapshot = context.snapshot()
            var nextKeys: Set<String> = []
            for scope in [ConversationLocationData.Scope.turn, .step] {
                guard let data = context.definition.buildLocationData(context: snapshot, scope: scope) else { continue }
                let dataKey = locationDataKey(data)
                locationDataByKey[dataKey] = data
                nextKeys.insert(dataKey)
            }
            for stale in context.locationKeys.subtracting(nextKeys) {
                locationDataByKey.removeValue(forKey: stale)
            }
            context.locationKeys = nextKeys
            guard let target = context.definition.target else { continue }
            guard let node = context.definition.buildViewNode(context: snapshot) else { continue }
            precondition(node.key == context.key,
                         "conversation Definition \(context.kind) produced unstable key \(node.key), expected \(context.key)")
            precondition(node.target == target,
                         "conversation Definition \(context.kind) produced \(node.target), expected \(target)")
            let previous = context.current[target] ?? nil
            context.current[target] = node
            if target == "chat" {
                insertChatNode(node, replacing: previous)
            } else if previous == nil {
                nodesByTarget[target, default: []].append(node)
            } else if let index = nodesByTarget[target]?.firstIndex(where: { $0.key == node.key }) {
                nodesByTarget[target]?[index] = node
            }
        }
    }

    /// Anchors a chat node into binary-sorted position while replacing a
    /// previous snapshot of the same context, mirroring the full-rebuild order:
    /// ascending anchor, `key` as the deterministic tie-break.
    private func insertChatNode(_ node: ConversationViewNode, replacing previous: ConversationViewNode?) {
        var nodes = nodesByTarget["chat"] ?? []
        if let previous, let index = nodes.firstIndex(where: { $0.key == previous.key }) {
            nodes.remove(at: index)
        }
        var lower = nodes.startIndex
        var upper = nodes.endIndex
        while lower < upper {
            let mid = (lower + upper) / 2
            if isOrdered(nodes[mid], before: node) {
                lower = mid + 1
            } else {
                upper = mid
            }
        }
        nodes.insert(node, at: lower)
        nodesByTarget["chat"] = nodes
    }

    private func isOrdered(_ lhs: ConversationViewNode, before rhs: ConversationViewNode) -> Bool {
        let leftAnchor = lhs.anchorSeq ?? .greatestFiniteMagnitude
        let rightAnchor = rhs.anchorSeq ?? .greatestFiniteMagnitude
        if leftAnchor == rightAnchor { return lhs.key < rhs.key }
        return leftAnchor < rightAnchor
    }

    private func locationDataKey(_ data: ConversationLocationData) -> String {
        "\(data.scope.rawValue):\(data.turn):\(data.step.map(String.init) ?? "-"):\(data.key)"
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
    /// Durable plugin events (for example `tool-workflow/*`) do not repeat
    /// turn/step fields, but the official assembler assigns them to the active
    /// location. Preserve that engine-owned placement separately from event data.
    private var inferredLocations: [Int: (turn: Int, step: Int?)] = [:]
    private var activeTurn: Int?
    private var activeStep: (turn: Int, step: Int)?

    init(entries: [ConversationEventInput]) {
        for entry in entries {
            scan(entry)
        }
    }

    /// Extends the index with one live tail event. Streamed events arrive in
    /// strictly ascending seq order, so late-extending facts (end statuses,
    /// inferred locations) never change already-emitted lookups.
    mutating func append(_ entry: ConversationEventInput) {
        scan(entry)
    }

    private mutating func scan(_ entry: ConversationEventInput) {
        let event = entry.event
        let explicitTurn = event.data.integer(named: "turn")
        if event.type == "turn/start", let explicitTurn {
            activeTurn = explicitTurn
            activeStep = nil
        }
        if event.type == "step/start", let explicitTurn,
           let explicitStep = event.data.integer(named: "step") {
            activeTurn = explicitTurn
            activeStep = (explicitTurn, explicitStep)
        }
        if explicitTurn == nil, let activeTurn {
            inferredLocations[event.seq] = activeStep?.turn == activeTurn
                ? (activeTurn, activeStep?.step)
                : (activeTurn, nil)
        }
        guard let turn = explicitTurn else { return }
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
        if event.type == "step/end", let endingStep = event.data.integer(named: "step"),
           activeStep?.turn == turn, activeStep?.step == endingStep {
            activeStep = nil
        }
        if event.type == "turn/end", activeTurn == turn {
            activeTurn = nil
            activeStep = nil
        }
    }

    func location(for event: SessionEventDTO) -> ConversationLocation {
        let inferred = inferredLocations[event.seq]
        guard let turnNumber = event.data.integer(named: "turn") ?? inferred?.turn,
              let facts = turns[turnNumber]
        else {
            return .session
        }
        let turn = makeTurn(number: turnNumber, facts: facts)
        guard let stepNumber = event.data.integer(named: "step") ?? inferred?.step else { return .turn(turn) }
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

private extension SessionEventDTO {
    /// True when this event can mutate engine-owned location facts: explicit
    /// turn/step fields, or turn/step boundary evidence the timeline scanner
    /// folds into active-location state. Content and durable plugin events
    /// never change facts already emitted for earlier sequences, so appends with
    /// `false` here are safe to accept incrementally.
    var affectsLocationFacts: Bool {
        type.hasPrefix("turn/") || type.hasPrefix("step/") || data.integer(named: "turn") != nil
    }
}
