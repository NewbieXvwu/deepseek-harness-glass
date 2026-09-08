import Foundation

/// Transport-free projection boundary for one addressed Session runtime state.
///
/// The engine accepts only the already-authenticated Journal + Control domain
/// state assembled by `SessionRuntime`. It never observes carrier frames,
/// endpoints, cookies, reconnect tasks, or command receipts.
final class SessionProjectionEngine {
    struct Snapshot {
        let generation: RemoteConnectionGeneration
        let address: SessionAddress
        let chatNodes: [ConversationViewNode]
        let trajectoryNodes: [ConversationViewNode]
        let toolCalls: [CoreToolCallNode]
        let queue: [RemoteSessionQueuedItem]
        let jobs: [RemoteSessionJob]
        let projectionValues: [String: RemoteJSONValue]
        let projectionSequence: SessionSeq
        let isRunning: Bool
        let modelSelection: RemoteModelSelection?
        let hasMoreHistory: Bool
    }

    private let conversation: ConversationNodeReducer

    init(
        definitions: [AnyConversationNodeDefinition] = ConversationCoreNodeRegistry.initialDefinitions()
    ) {
        conversation = ConversationNodeReducer(definitions: definitions)
    }

    func project(_ state: SessionRuntimeState) -> Snapshot {
        let inputs = state.journal.records.map(ConversationEventInput.init(remoteRecord:))
        _ = conversation.replaceWindow(inputs, hasMore: state.journal.hasMore)

        let chatNodes = conversation.snapshot(target: "chat")
        let baseline = state.control?.projections ?? state.journal.projections
        return Snapshot(
            generation: state.journal.generation,
            address: state.journal.address,
            chatNodes: chatNodes,
            trajectoryNodes: conversation.snapshot(target: "trajectory"),
            toolCalls: chatNodes.compactMap { $0.data as? CoreToolCallNode },
            queue: state.control?.queue ?? [],
            jobs: state.control?.jobs ?? [],
            projectionValues: baseline.values,
            projectionSequence: baseline.asOfSeq,
            isRunning: runningState(in: inputs),
            modelSelection: modelSelection(in: baseline),
            hasMoreHistory: state.journal.hasMore
        )
    }

    private func runningState(in inputs: [ConversationEventInput]) -> Bool {
        var running = false
        for input in inputs {
            switch input.event.type {
            case "turn/start", "assistant/chunk": running = true
            case "turn/end": running = false
            default: break
            }
        }
        return running
    }

    private func modelSelection(in baseline: RemoteSessionProjectionBaseline) -> RemoteModelSelection? {
        guard case let .object(selection)? = baseline.values["model/selection"],
              case let .object(next)? = selection["next"],
              case let .string(provider)? = next["provider"],
              case let .string(model)? = next["model"]
        else { return nil }

        let reasoningEffort: String?
        if case let .string(value)? = next["reasoningEffort"] {
            reasoningEffort = value
        } else {
            reasoningEffort = nil
        }
        return .init(provider: provider, model: model, reasoningEffort: reasoningEffort)
    }
}
