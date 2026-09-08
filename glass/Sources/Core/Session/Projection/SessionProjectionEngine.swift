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
        let toolInvocations: [SessionToolInvocation]
        let queue: [RemoteSessionQueuedItem]
        let jobs: [RemoteSessionJob]
        let projectionValues: [String: RemoteJSONValue]
        let projectionSequence: SessionSeq
        let isRunning: Bool
        let modelSelection: RemoteModelSelection?
        let hasMoreHistory: Bool
    }

    struct JournalFoldCursor: Equatable {
        let generation: RemoteConnectionGeneration
        let address: SessionAddress
        let revision: UInt64
        let recordCount: Int

        init(_ journal: SessionJournalSnapshot) {
            generation = journal.generation
            address = journal.address
            revision = journal.revision
            recordCount = journal.records.count
        }
    }

    enum JournalFoldPlan: Equatable {
        case replace
        case append(startRecordIndex: Int)
        case unchanged
    }

    private let conversation: ConversationNodeReducer
    private let tools = ToolInvocationProjector()
    private var journalCursor: JournalFoldCursor?
    private var running = false
    private var chatNodes: [ConversationViewNode] = []
    private var trajectoryNodes: [ConversationViewNode] = []
    private var toolCalls: [CoreToolCallNode] = []
    private var toolInvocations: [SessionToolInvocation] = []

    init(
        definitions: [AnyConversationNodeDefinition] = ConversationCoreNodeRegistry.initialDefinitions()
    ) {
        conversation = ConversationNodeReducer(definitions: definitions)
    }

    func project(_ state: SessionRuntimeState) -> Snapshot {
        foldDurableJournal(state.journal)

        let baseline = state.control?.projections ?? state.journal.projections
        return Snapshot(
            generation: state.journal.generation,
            address: state.journal.address,
            chatNodes: chatNodes,
            trajectoryNodes: trajectoryNodes,
            toolCalls: toolCalls,
            toolInvocations: toolInvocations,
            queue: state.control?.queue ?? [],
            jobs: state.control?.jobs ?? [],
            projectionValues: baseline.values,
            projectionSequence: baseline.asOfSeq,
            isRunning: running,
            modelSelection: modelSelection(in: baseline),
            hasMoreHistory: state.journal.hasMore
        )
    }

    static func journalFoldPlan(
        previous: JournalFoldCursor?,
        journal: SessionJournalSnapshot
    ) -> JournalFoldPlan {
        // revision == 0 is reserved for hand-built fixtures and other snapshots
        // outside the production Journal mutation path. Always refold them so a
        // test or adapter cannot accidentally claim incremental authority.
        guard journal.revision > 0,
              let previous,
              previous.generation == journal.generation,
              previous.address == journal.address
        else { return .replace }

        if journal.revision == previous.revision {
            return journal.records.count == previous.recordCount ? .unchanged : .replace
        }

        guard previous.revision < UInt64.max,
              journal.revision == previous.revision + 1,
              case let .append(startRecordIndex) = journal.mutation,
              startRecordIndex == previous.recordCount,
              startRecordIndex >= 0,
              startRecordIndex < journal.records.count
        else { return .replace }

        for record in journal.records[startRecordIndex...] {
            guard case .event = record else { return .replace }
        }
        return .append(startRecordIndex: startRecordIndex)
    }

    private func foldDurableJournal(_ journal: SessionJournalSnapshot) {
        let plan = Self.journalFoldPlan(previous: journalCursor, journal: journal)
        switch plan {
        case .replace:
            let inputs = journal.records.map(ConversationEventInput.init(remoteRecord:))
            _ = conversation.replaceWindow(inputs, hasMore: journal.hasMore)
            _ = tools.replaceWindow(journal.records, sessionCWD: journal.header.cwd)
            running = runningState(in: inputs)
            refreshDurableSnapshots(toolStateChanged: true)

        case let .append(startRecordIndex):
            var toolStateChanged = false
            for record in journal.records[startRecordIndex...] {
                let input = ConversationEventInput(remoteRecord: record)
                _ = conversation.append(input)
                if case let .event(event) = record {
                    tools.appendInPlace(event, sessionCWD: journal.header.cwd)
                    if event.type == "tool/call" || event.type == "tool/result" {
                        toolStateChanged = true
                    }
                }
                applyRunningState(input.event)
            }
            refreshDurableSnapshots(toolStateChanged: toolStateChanged)

        case .unchanged:
            break
        }
        journalCursor = .init(journal)
    }

    private func refreshDurableSnapshots(toolStateChanged: Bool) {
        chatNodes = conversation.snapshot(target: "chat")
        trajectoryNodes = conversation.snapshot(target: "trajectory")
        toolCalls = chatNodes.compactMap { $0.data as? CoreToolCallNode }
        if toolStateChanged {
            toolInvocations = tools.snapshot()
        }
    }

    private func runningState(in inputs: [ConversationEventInput]) -> Bool {
        var value = false
        for input in inputs {
            switch input.event.type {
            case "turn/start", "assistant/chunk": value = true
            case "turn/end": value = false
            default: break
            }
        }
        return value
    }

    private func applyRunningState(_ event: SessionEventDTO) {
        switch event.type {
        case "turn/start", "assistant/chunk": running = true
        case "turn/end": running = false
        default: break
        }
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
