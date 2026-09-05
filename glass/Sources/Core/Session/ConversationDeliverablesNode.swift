import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Immutable turn-scoped artifacts reported by successful mutation tool views.
/// Source: `packages/client/ui-deliverables/src/client/turn-deliverables.ts`.
struct CoreDeliverablesTurnData: Equatable {
    struct ProducedPath: Equatable {
        let seq: Int
        let path: String
    }

    let produced: [ProducedPath]

    /// Official closing-assistant cut: preserve first-seen order while excluding
    /// mutations that settled after the closing assistant sequence.
    func paths(forClosingSequence sequence: Int = .max) -> [String] {
        var seen = Set<String>()
        return produced.compactMap { item in
            guard item.seq <= sequence, seen.insert(item.path).inserted else { return nil }
            return item.path
        }
    }
}

/// Official state-only `deliverables` definition. It deliberately publishes
/// turn location data rather than a chat node; a later turn-tail renderer uses
/// this typed value to render chips and safe file mentions.
struct DeliverablesDefinition: ConversationNodeDefinition {
    struct State {
        let turn: Int
        var calls: [String: String?]
        var produced: [CoreDeliverablesTurnData.ProducedPath]
    }

    let kind = "deliverables"
    let target: String? = nil

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        guard let turn = event.data.deliverablesInteger(named: "turn") else { return nil }
        switch event.type {
        case "turn/start":
            return .init(id: String(turn), role: .start)
        case "tool/call":
            return .init(id: String(turn), role: .update)
        case "tool/result" where event.isDeliverablesAppendSurface:
            return .init(id: String(turn), role: .update)
        default:
            return nil
        }
    }

    func start(
        context _: ConversationNodeContext<State>,
        match: ConversationMatch,
        reader _: any ConversationContextReader
    ) -> State {
        guard let turn = match.event.data.deliverablesInteger(named: "turn") else {
            preconditionFailure("deliverables start requires turn/start turn")
        }
        return .init(turn: turn, calls: [:], produced: [])
    }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        guard var state = context.state else { preconditionFailure("deliverables update requires turn/start") }
        switch match.event.type {
        case "tool/call":
            guard let callID = match.event.data.deliverablesString(named: "callId"), !callID.isEmpty else { return state }
            state.calls[callID] = mutationPath(
                name: match.event.data.deliverablesString(named: "name") ?? "",
                arguments: match.event.data.deliverablesString(named: "arguments") ?? ""
            )
            return state
        case "tool/result":
            guard !match.event.data.deliverablesResultIsError,
                  let message = match.event.data.deliverablesObject(named: "message"),
                  let source = message["source"]?.objectValue,
                  let callID = source["callId"]?.stringValue,
                  !callID.isEmpty
            else { return state }
            guard let path = state.calls[callID] ?? nil else { return state }
            state.produced.append(.init(seq: match.event.seq, path: path))
            return state
        default:
            return state
        }
    }

    func buildLocationData(
        context: ConversationNodeContext<State>,
        scope: ConversationLocationData.Scope
    ) -> ConversationLocationData? {
        guard scope == .turn, let state = context.state else { return nil }
        return .init(
            scope: .turn,
            turn: state.turn,
            step: nil,
            key: kind,
            value: CoreDeliverablesTurnData(produced: state.produced)
        )
    }

    private func mutationPath(name: String, arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let args = value.objectValue
        else { return nil }
        func path(_ key: String) -> String? {
            guard let value = args[key]?.stringValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        switch name {
        case "write":
            guard args["content"]?.stringValue != nil else { return nil }
            return path("file_path")
        case "edit":
            guard let old = args["old_string"]?.stringValue, !old.isEmpty,
                  let new = args["new_string"]?.stringValue, old != new,
                  args["replace_all"] == nil || args["replace_all"]?.boolValue != nil
            else { return nil }
            return path("file_path")
        case "str_replace_editor":
            guard let target = path("path"), let command = args["command"]?.stringValue else { return nil }
            switch command {
            case "create":
                return args["file_text"]?.stringValue != nil ? target : nil
            case "str_replace":
                guard let old = args["old_str"]?.stringValue, !old.isEmpty,
                      args["new_str"] == nil || args["new_str"]?.stringValue != nil
                else { return nil }
                return target
            case "insert":
                guard let line = args["insert_line"]?.numberValue, line.isFinite, line.rounded(.towardZero) == line, line >= 0,
                      args["new_str"]?.stringValue != nil
                else { return nil }
                return target
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

private extension SessionEventDTO {
    var isDeliverablesAppendSurface: Bool { surfaceOp?.stringValue == "append" }
}

private extension JSONValue {
    func deliverablesObject(named key: String) -> [String: JSONValue]? { objectValue?[key]?.objectValue }
    func deliverablesString(named key: String) -> String? { objectValue?[key]?.stringValue }
    func deliverablesInteger(named key: String) -> Int? {
        guard let number = objectValue?[key]?.numberValue,
              number.rounded(.towardZero) == number,
              number >= 0,
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }

    var deliverablesResultIsError: Bool {
        if deliverablesObject(named: "error") != nil { return true }
        let content = deliverablesObject(named: "message")?["content"]?.arrayValue ?? []
        return content.contains { $0.objectValue?["isError"]?.boolValue == true }
    }
}
