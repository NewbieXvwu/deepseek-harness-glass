import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Typed, renderer-safe projection of one durable official workflow run.
/// Source: `packages/client/ui-workflow-run/src/client/workflow-definition.ts`
/// at the locked official commit. Raw event data never reaches SwiftUI.
struct CoreWorkflowRunNode: Equatable {
    enum Status: String, Equatable {
        case running
        case completed
        case failed
        case cancelled
        case interrupted
    }

    struct Member: Equatable {
        let seq: Int
        let label: String
        let phase: String?
        let childID: String
        let status: Status
    }

    struct Phase: Equatable {
        let key: String
        let phase: String?
        let members: [Member]
    }

    let name: String
    let status: Status
    let phases: [Phase]
}

/// Durable official `tool-workflow/*` event family. The node is keyed by runId,
/// records only members that actually started, and preserves the exact absent
/// (`nil`) versus empty-string phase identity required by the official panel.
private struct WorkflowRunDefinition: ConversationNodeDefinition {
    private enum StopReason: String {
        case completed
        case cancelled
        case error
    }

    private enum AgentOutcome: String {
        case completed
        case failed
        case cancelled
    }

    struct MemberState {
        let seq: Int
        let label: String
        let phase: String?
        let childID: String
        let outcome: AgentOutcome?
    }

    struct State {
        let name: String
        let stopReason: StopReason?
        let members: [MemberState]
    }

    let kind = "workflow-run"
    let target: String? = "chat"

    func match(_ event: SessionEventDTO) -> ConversationMatchResult? {
        guard let runID = event.data.workflowString(named: "runId"), !runID.isEmpty else { return nil }
        switch event.type {
        case "tool-workflow/run-start":
            return .init(id: runID, role: .start)
        case "tool-workflow/agent-start", "tool-workflow/agent-end", "tool-workflow/run-end":
            return .init(id: runID, role: .update)
        default:
            return nil
        }
    }

    func start(
        context _: ConversationNodeContext<State>,
        match: ConversationMatch,
        reader _: any ConversationContextReader
    ) -> State {
        // An invalid Host payload must not crash the session reducer. The empty
        // display name remains distinguishable and is rendered by the official
        // locale fallback in the target renderer rather than invented copy.
        .init(name: match.event.data.workflowString(named: "name") ?? "", stopReason: nil, members: [])
    }

    func update(context: ConversationNodeContext<State>, match: ConversationMatch) -> State {
        guard let state = context.state else { preconditionFailure("workflow-run update requires start") }
        switch match.event.type {
        case "tool-workflow/agent-start":
            guard let seq = match.event.data.workflowPositiveInteger(named: "seq"),
                  let childID = match.event.data.workflowString(named: "childId"), !childID.isEmpty
            else { return state }
            // The official invariant rejects repeated member sequences. Host
            // input is treated as authority, but duplicate live/replay evidence
            // must never fabricate an extra renderer row.
            guard !state.members.contains(where: { $0.seq == seq }) else { return state }
            let phase = match.event.data.workflowString(named: "phase")
            return .init(
                name: state.name,
                stopReason: state.stopReason,
                members: state.members + [.init(
                    seq: seq,
                    label: match.event.data.workflowString(named: "label") ?? "",
                    phase: phase,
                    childID: childID,
                    outcome: nil
                )]
            )
        case "tool-workflow/agent-end":
            guard let seq = match.event.data.workflowPositiveInteger(named: "seq"),
                  let rawOutcome = match.event.data.workflowString(named: "outcome"),
                  let outcome = AgentOutcome(rawValue: rawOutcome)
            else { return state }
            return .init(
                name: state.name,
                stopReason: state.stopReason,
                members: state.members.map { member in
                    member.seq == seq ? .init(
                        seq: member.seq,
                        label: member.label,
                        phase: member.phase,
                        childID: member.childID,
                        outcome: outcome
                    ) : member
                }
            )
        case "tool-workflow/run-end":
            guard let rawReason = match.event.data.workflowString(named: "stopReason"),
                  let stopReason = StopReason(rawValue: rawReason)
            else { return state }
            return .init(name: state.name, stopReason: stopReason, members: state.members)
        default:
            return state
        }
    }

    func buildViewNode(context: ConversationNodeContext<State>) -> ConversationViewNode? {
        guard let state = context.state, let start = context.start else { return nil }
        let interrupted = state.stopReason == nil && workflowLocationIsClosed(start.location)
        let status: CoreWorkflowRunNode.Status
        if let stopReason = state.stopReason {
            status = workflowStatus(stopReason)
        } else {
            status = interrupted ? .interrupted : .running
        }

        var grouped: [(key: String, phase: String?, members: [CoreWorkflowRunNode.Member])] = []
        for member in state.members {
            let key = workflowPhaseKey(member.phase)
            let memberStatus: CoreWorkflowRunNode.Status
            if let outcome = member.outcome {
                memberStatus = workflowStatus(outcome)
            } else {
                memberStatus = interrupted ? .interrupted : .running
            }
            let projected = CoreWorkflowRunNode.Member(
                seq: member.seq,
                label: member.label,
                phase: member.phase,
                childID: member.childID,
                status: memberStatus
            )
            if let index = grouped.firstIndex(where: { $0.key == key }) {
                grouped[index].members.append(projected)
            } else {
                grouped.append((key: key, phase: member.phase, members: [projected]))
            }
        }
        let data = CoreWorkflowRunNode(
            name: state.name,
            status: status,
            phases: grouped.map { .init(key: $0.key, phase: $0.phase, members: $0.members) }
        )
        return .init(
            key: context.key,
            kind: kind,
            id: context.id,
            target: "chat",
            data: data,
            anchorSeq: Double(start.event.seq),
            visibility: .visible
        )
    }

    private func workflowStatus(_ reason: StopReason) -> CoreWorkflowRunNode.Status {
        switch reason {
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .error: return .failed
        }
    }

    private func workflowStatus(_ outcome: AgentOutcome) -> CoreWorkflowRunNode.Status {
        switch outcome {
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
}

/// Collision-free key preserving the official missing/empty/value phase split.
func workflowPhaseKey(_ phase: String?) -> String {
    guard let phase else { return "missing" }
    // JavaScript `String.length` counts UTF-16 code units. Keep the stable
    // key byte-for-byte compatible with the official definition for emoji and
    // other non-BMP phase names, not merely ASCII fixtures.
    return "value:\(phase.utf16.count):\(phase)"
}

private func workflowLocationIsClosed(_ location: ConversationLocation) -> Bool {
    switch location {
    case let .step(turn, step): return turn.status == .closed || step.status == .closed
    case let .turn(turn): return turn.status == .closed
    case .session, .unresolved: return false
    }
}

private extension JSONValue {
    func workflowString(named key: String) -> String? { objectValue?[key]?.stringValue }

    func workflowPositiveInteger(named key: String) -> Int? {
        guard let number = objectValue?[key]?.numberValue,
              number.rounded(.towardZero) == number,
              number > 0,
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}
