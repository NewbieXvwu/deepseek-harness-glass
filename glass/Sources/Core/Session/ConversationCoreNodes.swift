import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

// MARK: - Core-render payloads

/// A typed, order-preserving content block. The original event remains in the
/// reducer evidence; the target payload carries only Core-classified structure.
struct ConversationContentBlock {
    enum Kind: String, Equatable {
        case text
        case reasoning
        case image
        case toolCall = "tool-call"
        case other
    }

    let kind: Kind
    let text: String?
    let callID: String?
    let name: String?
    let argumentsRaw: String?
    let raw: JSONValue
}

struct CoreUserMessageNode {
    enum Kind: String, Equatable { case user, context }
    let kind: Kind
    let seq: Int
    let time: Double
    let messageID: String
    let content: [ConversationContentBlock]
    let sourceKind: String
    let sourcePlugin: String?
}

struct CoreAssistantNode {
    enum Status: String, Equatable { case running, settled, interrupted }
    let status: Status
    let turn: Int
    let step: Int
    let seq: Int
    let time: Double
    let messageID: String?
    let blocks: [ConversationContentBlock]
    let firstTokenTime: Double?
    let completedTime: Double?
    let usage: JSONValue?
}

struct CoreToolCallNode {
    enum Status: String, Equatable { case running, settled, interrupted }
    let status: Status
    let callID: String
    let name: String
    let argumentsRaw: String
    let turn: Int
    let step: Int
    let callTime: Double
    let resultSeq: Int?
    let resultTime: Double?
    let resultContent: [ConversationContentBlock]
    let isError: Bool
    let errorCode: String?
    let callView: JSONValue?
    let resultView: JSONValue?
}

struct CoreRetryAttempt: Equatable {
    enum State: String, Equatable { case scheduled, started, cancelled }
    let seq: Int
    let time: Double
    let retry: Int
    let state: State
}

struct CoreRetryNode {
    let turn: Int
    let step: Int
    let attempts: [CoreRetryAttempt]
}

struct CoreBoundaryNode {
    enum Kind: String, Equatable { case turn, step }
    let kind: Kind
    let turn: Int
    let step: Int?
    let startSeq: Int
    let endSeq: Int?
    let status: String
}

struct CoreTurnErrorNode {
    let turn: Int
    let step: Int
    let seq: Int
    let time: Double
    let message: String
    let code: String?
    let hiddenByRetry: Bool
}

struct CoreCompactionNode {
    let compactionID: String
    let seq: Int
    let time: Double
    let summary: String?
    let summaryEventSeq: Int?
    let shadowedItemCount: Int?
    let shadowedTokenCount: Int?
}

/// The Core registry used by the Session reducer for the first official
/// conversation family. Feature/UI uses only reducer snapshots, never this
/// registry or raw event DTOs.
enum ConversationCoreNodeRegistry {
    static func initialDefinitions() -> [AnyConversationNodeDefinition] {
        [
            .init(BoundaryDefinition()),
            .init(InputMessageDefinition()),
            .init(AssistantStepDefinition()),
            .init(ToolDefinition()),
            .init(RetryDefinition()),
            .init(TurnErrorDefinition()),
            .init(CompactionDefinition())
        ]
    }
}

// MARK: - User/context input

private struct InputMessageDefinition: ConversationNodeDefinition {
    typealias State = CoreUserMessageNode
    let kind = "input-message"
    let target: String? = "chat"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        guard event.type == "user/message", event.isAppendSurface else { return nil }
        guard !event.isCompactionCheckpoint, let id = event.data.string(named: "id"), !id.isEmpty else { return nil }
        return .init(id: id, role: .start)
    }

    func start(context _: ConversationNodeContext<CoreUserMessageNode>, match: ConversationMatch, reader _: any ConversationContextReader) -> CoreUserMessageNode {
        let data = match.event.data
        let source = data.object(named: "source")
        let sourceKind = source?.string(named: "kind") ?? "unknown"
        return .init(
            kind: sourceKind == "user" ? .user : .context,
            seq: match.event.seq,
            time: match.event.time,
            messageID: data.string(named: "id") ?? match.event.seq.description,
            content: data.content(named: "content"),
            sourceKind: sourceKind,
            sourcePlugin: source?.string(named: "plugin")
        )
    }

    func update(context: ConversationNodeContext<CoreUserMessageNode>, match _: ConversationMatch) -> CoreUserMessageNode {
        guard let state = context.state else { preconditionFailure("input-message update requires start") }
        return state
    }

    func buildViewNode(context: ConversationNodeContext<CoreUserMessageNode>) -> ConversationViewNode? {
        guard let state = context.state else { return nil }
        return chatNode(context: context, kind: state.kind == .user ? "user" : "context", anchorSeq: state.seq, data: state)
    }
}

// MARK: - Step-owned assistant chunks, final messages and thinking blocks

private struct AssistantStepDefinition: ConversationNodeDefinition {
    struct State {
        let turn: Int
        let step: Int
        var blocks: [Int: ConversationContentBlock]
        var firstVisibleSeq: Int?
        var firstVisibleTime: Double?
        var firstTokenTime: Double?
        var final: Final?
        var usage: JSONValue?
        var resetGeneration: Int

        struct Final {
            let seq: Int
            let time: Double
            let messageID: String?
            let blocks: [ConversationContentBlock]
            let usage: JSONValue?
        }
    }

    let kind = "assistant-step"
    let target: String? = "chat"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        switch event.type {
        case "step/start":
            guard let turn = event.data.coreInteger(named: "turn"), let step = event.data.coreInteger(named: "step") else { return nil }
            return .init(id: "\(turn):\(step)", role: .start)
        case "assistant/chunk":
            guard let turn = event.data.coreInteger(named: "turn"), let step = event.data.coreInteger(named: "step") else { return nil }
            return .init(id: "\(turn):\(step)", role: .update)
        case "assistant/message":
            guard event.isAppendSurface, let turn = event.data.coreInteger(named: "turn"), let step = event.data.coreInteger(named: "step") else { return nil }
            return .init(id: "\(turn):\(step)", role: .update)
        case "llm/retry":
            guard let turn = event.data.coreInteger(named: "turn"), let step = event.data.coreInteger(named: "step") else { return nil }
            return .init(id: "\(turn):\(step)", role: .update)
        default:
            return nil
        }
    }

    func start(context _: ConversationNodeContext<State>, match: ConversationMatch, reader _: any ConversationContextReader) -> State {
        guard let turn = match.event.data.coreInteger(named: "turn"), let step = match.event.data.coreInteger(named: "step") else {
            preconditionFailure("assistant-step start requires step coordinates")
        }
        return .init(turn: turn, step: step, blocks: [:], firstVisibleSeq: nil, firstVisibleTime: nil, firstTokenTime: nil, final: nil, usage: nil, resetGeneration: 0)
    }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        guard var state = context.state else { preconditionFailure("assistant-step update requires start") }
        switch match.event.type {
        case "llm/retry":
            state.blocks = [:]
            state.firstVisibleSeq = nil
            state.firstVisibleTime = nil
            state.final = nil
            state.usage = nil
            state.resetGeneration += 1
        case "assistant/message":
            let message = match.event.data.object(named: "message")
            let blocks = message?.content(named: "content") ?? []
            state.final = .init(
                seq: match.event.seq,
                time: match.event.time,
                messageID: message?.string(named: "id"),
                blocks: blocks,
                usage: match.event.data.value(named: "usage")
            )
            state.usage = match.event.data.value(named: "usage")
        case "assistant/chunk":
            apply(chunkEvent: match.event, into: &state)
        default:
            break
        }
        return state
    }

    func publication(for match: ConversationMatch) -> ConversationPublication {
        guard match.event.type == "assistant/chunk" else {
            return match.event.type == "step/start" ? .none : .immediate
        }
        let type = match.event.data.object(named: "chunk")?.string(named: "type")
        return type == "usage" || type == "finish" ? .none : .animationFrame
    }

    func buildLocationData(context: ConversationNodeContext<State>, scope: ConversationLocationData.Scope) -> ConversationLocationData? {
        guard scope == .step, let payload = projected(context) else { return nil }
        return .init(scope: .step, turn: payload.turn, step: payload.step, key: kind, value: payload)
    }

    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
        guard let projectedPayload = projected(context) else { return nil }
        let visible = projectedPayload.blocks.contains { block in
            (block.kind == .text || block.kind == .reasoning) && !(block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let boundary = context.start?.location.closedEvent
        let interrupted = projectedPayload.status == .running && visible && boundary != nil
        let payload: CoreAssistantNode
        if let boundary, interrupted {
            payload = .init(status: .interrupted, turn: projectedPayload.turn, step: projectedPayload.step, seq: boundary.seq, time: boundary.time, messageID: nil, blocks: projectedPayload.blocks, firstTokenTime: projectedPayload.firstTokenTime, completedTime: boundary.time, usage: projectedPayload.usage)
        } else {
            payload = projectedPayload
        }
        guard payload.status != .running || visible else { return nil }
        return interrupted
            ? chatNode(context: context, kind: "assistant-step", anchor: Double(payload.seq) - 0.9, data: payload)
            : chatNode(context: context, kind: "assistant-step", anchorSeq: payload.seq, data: payload)
    }

    private func apply(chunkEvent event: SessionEventDTO, into state: inout State) {
        guard let chunk = event.data.object(named: "chunk"), let type = chunk.string(named: "type") else { return }
        let index = chunk.coreInteger(named: "index") ?? 0
        switch type {
        case "block-start":
            state.blocks[index] = .init(kind: .other, text: nil, callID: nil, name: nil, argumentsRaw: nil, raw: chunk.value(named: "block") ?? .null)
        case "text-delta", "reasoning-delta":
            let previous = state.blocks[index]
            let text = (previous?.text ?? "") + (chunk.string(named: "text") ?? "")
            state.blocks[index] = .init(kind: type == "text-delta" ? .text : .reasoning, text: text, callID: nil, name: nil, argumentsRaw: nil, raw: .object(chunk))
            markVisible(event: event, state: &state, token: true)
        case "tool-call-delta":
            let previous = state.blocks[index]
            let arguments = (previous?.argumentsRaw ?? "") + (chunk.string(named: "argumentsDelta") ?? "")
            state.blocks[index] = .init(kind: .toolCall, text: nil, callID: previous?.callID ?? chunk.string(named: "id"), name: chunk.string(named: "name") ?? previous?.name, argumentsRaw: arguments, raw: .object(chunk))
            markVisible(event: event, state: &state, token: true)
        case "block-end":
            if let block = chunk.value(named: "block") { state.blocks[index] = block.asContentBlock }
            markVisible(event: event, state: &state, token: false)
        case "usage":
            state.usage = chunk.value(named: "usage")
        default:
            break
        }
    }

    private func markVisible(event: SessionEventDTO, state: inout State, token: Bool) {
        let visible = state.blocks.values.contains { block in
            (block.kind == .text || block.kind == .reasoning || block.kind == .toolCall)
                && !(block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false)
        }
        if visible && state.firstVisibleSeq == nil {
            state.firstVisibleSeq = event.seq
            state.firstVisibleTime = event.time
        }
        if token && state.firstTokenTime == nil { state.firstTokenTime = event.time }
    }

    private func projected(_ context: ConversationNodeContext<State>) -> CoreAssistantNode? {
        guard let state = context.state else { return nil }
        let blocks = state.final?.blocks ?? state.blocks.keys.sorted().compactMap { state.blocks[$0] }
        guard let first = context.matches.first else { return nil }
        if let final = state.final {
            return .init(status: .settled, turn: state.turn, step: state.step, seq: final.seq, time: final.time, messageID: final.messageID, blocks: final.blocks, firstTokenTime: state.firstTokenTime, completedTime: final.time, usage: final.usage)
        }
        return .init(status: .running, turn: state.turn, step: state.step, seq: state.firstVisibleSeq ?? first.event.seq, time: state.firstVisibleTime ?? first.event.time, messageID: nil, blocks: blocks, firstTokenTime: state.firstTokenTime, completedTime: nil, usage: state.usage)
    }
}

// MARK: - Tool call/result

private struct ToolDefinition: ConversationNodeDefinition {
    struct State {
        let callID: String
        let name: String
        let argumentsRaw: String
        let turn: Int
        let step: Int
        let callTime: Double
        let callView: JSONValue?
        var result: Result?
        struct Result {
            let seq: Int
            let time: Double
            let content: [ConversationContentBlock]
            let isError: Bool
            let errorCode: String?
            let resultView: JSONValue?
        }
    }

    let kind = "tool-call"
    let target: String? = "chat"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        if event.type == "tool/call", let id = event.data.string(named: "callId"), !id.isEmpty { return .init(id: id, role: .start) }
        if event.type == "tool/result", event.isAppendSurface,
           let message = event.data.object(named: "message"),
           let source = message.object(named: "source"),
           let id = source.string(named: "callId"), !id.isEmpty { return .init(id: id, role: .update) }
        return nil
    }

    func start(context _: ConversationNodeContext<State>, match: ConversationMatch, reader _: any ConversationContextReader) -> State {
        let data = match.event.data
        guard let callID = data.string(named: "callId"), let name = data.string(named: "name") else { preconditionFailure("tool-call requires callId/name") }
        return .init(callID: callID, name: name, argumentsRaw: data.string(named: "arguments") ?? "", turn: data.coreInteger(named: "turn") ?? 0, step: data.coreInteger(named: "step") ?? 0, callTime: match.event.time, callView: match.view?.for == "call" ? match.view?.view : nil, result: nil)
    }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        guard var state = context.state else { preconditionFailure("tool result update requires call") }
        guard match.event.type == "tool/result" else { return state }
        let data = match.event.data
        let message = data.object(named: "message")
        let result = message?.content(named: "content") ?? []
        let error = data.object(named: "error")
        state.result = .init(seq: match.event.seq, time: match.event.time, content: result, isError: result.contains { $0.raw.objectValue?["isError"]?.boolValue == true } || error != nil, errorCode: error?.string(named: "code"), resultView: match.view?.for == "result" ? match.view?.view : nil)
        return state
    }

    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
        guard let state = context.state else { return nil }
        let result = state.result
        let boundary = result == nil ? context.start?.location.closedEvent : nil
        let interrupted = boundary != nil
        let payload = CoreToolCallNode(status: result == nil ? (interrupted ? .interrupted : .running) : .settled, callID: state.callID, name: state.name, argumentsRaw: state.argumentsRaw, turn: state.turn, step: state.step, callTime: state.callTime, resultSeq: result?.seq ?? boundary?.seq, resultTime: result?.time ?? boundary?.time, resultContent: result?.content ?? [], isError: result?.isError ?? interrupted, errorCode: result?.errorCode ?? (interrupted ? "interrupted" : nil), callView: state.callView, resultView: result?.resultView)
        if let boundary {
            return chatNode(context: context, kind: "tool-call", anchor: Double(boundary.seq) - 0.8, data: payload)
        }
        return chatNode(context: context, kind: "tool-call", anchorSeq: context.start?.event.seq ?? result?.seq ?? 0, data: payload)
    }
}

// MARK: - Retry and boundary/error state

private struct RetryDefinition: ConversationNodeDefinition {
    struct State { let turn: Int; let step: Int; var attempts: [CoreRetryAttempt] }
    let kind = "model-retry"
    let target: String? = "chat"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        guard let id = event.data.string(named: "retryId"), !id.isEmpty else { return nil }
        if event.type == "llm/retry" { return .init(id: id, role: (event.data.coreInteger(named: "retry") ?? 0) == 1 ? .start : .update) }
        return event.type == "llm/retry-started" ? .init(id: id, role: .update) : nil
    }

    func start(context _: ConversationNodeContext<State>, match: ConversationMatch, reader _: any ConversationContextReader) -> State {
        let data = match.event.data
        let attempt = CoreRetryAttempt(seq: match.event.seq, time: match.event.time, retry: data.coreInteger(named: "retry") ?? 1, state: .scheduled)
        return .init(turn: data.coreInteger(named: "turn") ?? 0, step: data.coreInteger(named: "step") ?? 0, attempts: [attempt])
    }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        guard var state = context.state else { preconditionFailure("retry update requires first retry") }
        let retry = match.event.data.coreInteger(named: "retry") ?? 0
        if match.event.type == "llm/retry" {
            state.attempts.append(.init(seq: match.event.seq, time: match.event.time, retry: retry, state: .scheduled))
        } else if match.event.type == "llm/retry-started" {
            state.attempts = state.attempts.map { $0.retry == retry ? .init(seq: $0.seq, time: $0.time, retry: $0.retry, state: .started) : $0 }
        }
        return state
    }

    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
        guard let state = context.state, let first = state.attempts.first else { return nil }
        let closed = context.start?.location.isClosedBoundary ?? false
        let attempts = state.attempts.enumerated().map { offset, value in
            offset == state.attempts.count - 1 && value.state == .scheduled && closed
                ? .init(seq: value.seq, time: value.time, retry: value.retry, state: .cancelled)
                : value
        }
        return chatNode(context: context, kind: "model-retry", anchorSeq: first.seq, data: CoreRetryNode(turn: state.turn, step: state.step, attempts: attempts))
    }
}

private struct BoundaryDefinition: ConversationNodeDefinition {
    struct State { let kind: CoreBoundaryNode.Kind; let turn: Int; let step: Int?; let startSeq: Int; var endSeq: Int? }
    let kind = "timeline-boundary"
    let target: String? = "timeline"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        switch event.type {
        case "turn/start": guard let turn = event.data.coreInteger(named: "turn") else { return nil }; return .init(id: "turn:\(turn)", role: .start)
        case "turn/end": guard let turn = event.data.coreInteger(named: "turn") else { return nil }; return .init(id: "turn:\(turn)", role: .update)
        case "step/start": guard let turn = event.data.coreInteger(named: "turn"), let step = event.data.coreInteger(named: "step") else { return nil }; return .init(id: "step:\(turn):\(step)", role: .start)
        case "step/end": guard let turn = event.data.coreInteger(named: "turn"), let step = event.data.coreInteger(named: "step") else { return nil }; return .init(id: "step:\(turn):\(step)", role: .update)
        default: return nil
        }
    }

    func start(context _: ConversationNodeContext<State>, match: ConversationMatch, reader _: any ConversationContextReader) -> State {
        let isStep = match.event.type == "step/start"
        return .init(kind: isStep ? .step : .turn, turn: match.event.data.coreInteger(named: "turn") ?? 0, step: isStep ? match.event.data.coreInteger(named: "step") : nil, startSeq: match.event.seq, endSeq: nil)
    }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        guard var state = context.state else { preconditionFailure("boundary update requires start") }
        state.endSeq = match.event.seq
        return state
    }

    func publication(for _: ConversationMatch) -> ConversationPublication { .none }

    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
        guard let state = context.state else { return nil }
        return .init(key: context.key, kind: "timeline-boundary", id: context.id, target: "timeline", data: CoreBoundaryNode(kind: state.kind, turn: state.turn, step: state.step, startSeq: state.startSeq, endSeq: state.endSeq, status: state.endSeq == nil ? "open" : "closed"))
    }
}

private struct TurnErrorDefinition: ConversationNodeDefinition {
    struct State { let turn: Int; var failure: (seq: Int, time: Double, message: String, code: String?)?; var hidden: Bool }
    let kind = "turn-error"
    let target: String? = "chat"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        if event.type == "turn/start", let turn = event.data.coreInteger(named: "turn") { return .init(id: turn.description, role: .start) }
        if event.type == "turn/end", event.data.object(named: "reason")?.string(named: "kind") == "error", let turn = event.data.coreInteger(named: "turn") { return .init(id: turn.description, role: .update) }
        if (event.type == "llm/retry" || event.type == "llm/retry-started"), let turn = event.data.coreInteger(named: "turn") { return .init(id: turn.description, role: .update) }
        return nil
    }

    func start(context _: ConversationNodeContext<State>, match: ConversationMatch, reader _: any ConversationContextReader) -> State { .init(turn: match.event.data.coreInteger(named: "turn") ?? 0, failure: nil, hidden: false) }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        guard var state = context.state else { preconditionFailure("turn error update requires start") }
        if match.event.type == "turn/end", let error = match.event.data.object(named: "reason")?.object(named: "error") {
            state.failure = (match.event.seq, match.event.time, error.string(named: "message") ?? error.string(named: "name") ?? "Unknown error", error.string(named: "code"))
        } else if match.event.type == "llm/retry" || match.event.type == "llm/retry-started" { state.hidden = true }
        return state
    }

    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
        guard let state = context.state, let failure = state.failure else { return nil }
        let step: Int
        switch context.start?.location {
        case let .step(_, located): step = located.step
        case let .turn(turn): step = turn.steps.last?.step ?? 0
        default: step = 0
        }
        let payload = CoreTurnErrorNode(turn: state.turn, step: step, seq: failure.seq, time: failure.time, message: failure.message, code: failure.code, hiddenByRetry: state.hidden)
        return chatNode(context: context, kind: "turn-error", anchor: Double(failure.seq), data: payload, visibility: state.hidden ? .hidden : .visible)
    }
}

// MARK: - Compaction lifecycle/checkpoint

private struct CompactionDefinition: ConversationNodeDefinition {
    struct State { var summary: ConversationMatch?; var checkpoint: ConversationMatch? }
    let kind = "compaction"
    let target: String? = "chat"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        if event.isCompactionCheckpoint, let source = event.data.object(named: "source"), let id = source.string(named: "compactionId") ?? event.data.string(named: "compactionId"), !id.isEmpty { return .init(id: id, role: .update) }
        guard event.type == "compaction/start" || event.type == "compaction/summary" || event.type == "compaction/end",
              event.data.string(named: "sourceCommandId") == nil,
              let id = event.data.string(named: "compactionId"), !id.isEmpty
        else { return nil }
        return .init(id: id, role: event.type == "compaction/start" ? .start : .update)
    }

    func start(context _: ConversationNodeContext<State>, match _: ConversationMatch, reader _: any ConversationContextReader) -> State { .init(summary: nil, checkpoint: nil) }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        var state = context.state ?? .init(summary: nil, checkpoint: nil)
        if match.event.type == "compaction/summary" { state.summary = match }
        if match.event.isCompactionCheckpoint { state.checkpoint = match }
        return state
    }

    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
        let state = context.state ?? fallback(context)
        guard let checkpoint = state.checkpoint else { return nil }
        let summary = state.summary?.event.data.string(named: "summary") ?? state.summary?.event.data.string(named: "text")
        let payload = CoreCompactionNode(compactionID: context.id, seq: checkpoint.event.seq, time: checkpoint.event.time, summary: summary, summaryEventSeq: state.summary?.event.seq, shadowedItemCount: state.summary?.event.data.coreInteger(named: "shadowedItemCount"), shadowedTokenCount: state.summary?.event.data.coreInteger(named: "shadowedTokenCount"))
        return chatNode(context: context, kind: "compaction", anchorSeq: payload.seq, data: payload)
    }

    private func fallback(_ context: ConversationNodeContext<State>) -> State {
        .init(summary: context.matches.first(where: { $0.event.type == "compaction/summary" }), checkpoint: context.matches.first(where: { $0.event.isCompactionCheckpoint }))
    }
}

// MARK: - Core-only JSON and node helpers

private func chatNode<State>(context: ConversationNodeContext<State>, kind: String, anchorSeq: Int, data: Any) -> ConversationViewNode {
    chatNode(context: context, kind: kind, anchor: Double(anchorSeq), data: data)
}

private func chatNode<State>(context: ConversationNodeContext<State>, kind: String, anchor: Double, data: Any, visibility: ChatConversationViewNode.Visibility = .visible) -> ConversationViewNode {
    .init(
        key: context.key,
        kind: kind,
        id: context.id,
        target: "chat",
        data: data,
        anchorSeq: anchor,
        visibility: visibility
    )
}

private extension SessionEventDTO {
    var isAppendSurface: Bool { surfaceOp?.stringValue == "append" }

    var isCompactionCheckpoint: Bool {
        guard type == "user/message", surfaceOp?.objectValue?[
            "op"
        ]?.stringValue == "replace" else { return false }
        let source = data.object(named: "source")
        return source?.string(named: "kind") == "plugin" && source?.string(named: "plugin") == "compact"
    }
}

private extension ConversationLocation {
    var closedEvent: SessionEventDTO? {
        switch self {
        case let .step(turn, step): return step.end ?? turn.end
        case let .turn(turn): return turn.end
        case .session, .unresolved: return nil
        }
    }

    var isClosedBoundary: Bool {
        switch self {
        case let .step(turn, step): return step.status == .closed || turn.status == .closed
        case let .turn(turn): return turn.status == .closed
        case .session, .unresolved: return false
        }
    }
}

private extension JSONValue {
    func value(named key: String) -> JSONValue? { objectValue?[key] }
    func object(named key: String) -> [String: JSONValue]? { value(named: key)?.objectValue }
    func string(named key: String) -> String? { value(named: key)?.stringValue }
    func coreInteger(named key: String) -> Int? {
        guard let number = value(named: key)?.numberValue, number.rounded(.towardZero) == number, number >= 0, number <= Double(Int.max) else { return nil }
        return Int(number)
    }

    func content(named key: String) -> [ConversationContentBlock] {
        value(named: key)?.arrayValue?.map(\.asContentBlock) ?? []
    }

    var asContentBlock: ConversationContentBlock {
        let object = objectValue
        switch object?.string(named: "type") {
        case "text": return .init(kind: .text, text: object?.string(named: "text"), callID: nil, name: nil, argumentsRaw: nil, raw: self)
        case "reasoning": return .init(kind: .reasoning, text: object?.string(named: "text"), callID: nil, name: nil, argumentsRaw: nil, raw: self)
        case "image": return .init(kind: .image, text: nil, callID: nil, name: nil, argumentsRaw: nil, raw: self)
        case "tool-call": return .init(kind: .toolCall, text: nil, callID: object?.string(named: "id"), name: object?.string(named: "name"), argumentsRaw: object?.string(named: "arguments"), raw: self)
        default: return .init(kind: .other, text: nil, callID: nil, name: nil, argumentsRaw: nil, raw: self)
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func value(named key: String) -> JSONValue? { self[key] }
    func object(named key: String) -> [String: JSONValue]? { self[key]?.objectValue }
    func string(named key: String) -> String? { self[key]?.stringValue }
    func coreInteger(named key: String) -> Int? {
        guard let number = self[key]?.numberValue, number.rounded(.towardZero) == number, number >= 0, number <= Double(Int.max) else { return nil }
        return Int(number)
    }
    func content(named key: String) -> [ConversationContentBlock] { self[key]?.arrayValue?.map(\.asContentBlock) ?? [] }
}
