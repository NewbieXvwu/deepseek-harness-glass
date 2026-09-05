import Combine
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Typed domain-intent boundary injected into the session feature. It carries
/// only session operations; wire envelopes, URL requests and transport clients
/// remain behind the production `SessionsAPI` implementation.
@MainActor
protocol NativeSessionAPI: Sendable {
    func history(sessionID: String, beforeSeq: Int?, maxMessages: Int?) async throws -> SessionHistoryResponse
    func prompt(sessionID: String, content: [SessionPromptContent], mode: SessionPromptMode) async throws -> SessionPromptResponse
    func cancel(sessionID: String) async throws -> SessionCancelResponse
    func updateQueue(_ request: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse
    func models(sessionID: String) async throws -> SessionModelsResponse
    func selectModel(_ request: SessionSelectModelRequest) async throws -> SessionSelectModelResponse
    func answerApproval(rpcID: String, sessionID: String, approvalID: String, outcome: ApprovalOutcome) async throws -> RPCReceipt
    func answerQuestion(rpcID: String, sessionID: String, answers: [QuestionAnswerResponse]) async throws -> RPCReceipt
    func cancelQuestion(rpcID: String) async throws -> RPCReceipt
}

extension SessionsAPI: NativeSessionAPI {}

extension NativeSessionAPI {
    /// Test fakes must opt in explicitly to queue mutation. Treat omitted seams
    /// as an unavailable Host rather than manufacturing an accepted response.
    func updateQueue(_: SessionUpdateQueueRequest) async throws -> SessionUpdateQueueResponse {
        throw DSHTransportError.invalidEndpoint
    }

    /// Model selection is unavailable unless a verified Host facade implements
    /// the RC8 `session.selectModel` operation.
    func selectModel(_: SessionSelectModelRequest) async throws -> SessionSelectModelResponse {
        throw DSHTransportError.invalidEndpoint
    }
}

/// Typed Host action seam for RC8 GoalBar. A successful RPC returns only a
/// compare-and-set reference (or clear receipt); visible state must still wait
/// for the authoritative `goal` whole projection update.
@MainActor
protocol NativeGoalAPI: Sendable {
    func edit(_ request: GoalEditRequest) async throws -> GoalReferenceResponse
    func pause(_ request: GoalReferenceRequest) async throws -> GoalReferenceResponse
    func resume(_ request: GoalReferenceRequest) async throws -> GoalReferenceResponse
    func clear(_ request: GoalReferenceRequest) async throws -> GoalClearResponse
}

extension CommandsAPI: NativeGoalAPI {}

/// Typed complete direct-child catalog boundary. UI requests refresh explicitly;
/// no local session summary may manufacture descendants when this API is absent.
@MainActor
protocol NativeSubagentCatalogAPI: Sendable {
    func list(parentSessionID: String) async throws -> SubagentListResponse
}

@MainActor
protocol NativeSubagentContinuationAPI: Sendable {
    func prompt(_ request: SubagentPromptRequest) async throws -> SubagentPromptResponse
    func interrupt(_ request: SubagentInterruptRequest) async throws -> SubagentInterruptResponse
}

extension SubagentsAPI: NativeSubagentCatalogAPI, NativeSubagentContinuationAPI {}

/// Read-only phase of the RC8 feedback controller. Items are always supplied by
/// the Host list response; mutations are added only behind the same typed seam.
@MainActor
protocol NativeMessageFeedbackAPI: Sendable {
    func list(sessionID: String) async throws -> MessageFeedbackListResponse
    func put(_ request: MessageFeedbackPutRequest) async throws -> MessageFeedbackPutResponse
    func delete(_ request: MessageFeedbackDeleteRequest) async throws -> MessageFeedbackDeleteResponse
}

extension NativeMessageFeedbackAPI {
    /// Read-only/absent feedback plugins must fail closed for a mutation rather
    /// than letting a local row pretend the rating was accepted.
    func put(_: MessageFeedbackPutRequest) async throws -> MessageFeedbackPutResponse {
        throw DSHTransportError.invalidEndpoint
    }

    func delete(_: MessageFeedbackDeleteRequest) async throws -> MessageFeedbackDeleteResponse {
        throw DSHTransportError.invalidEndpoint
    }
}

extension MessageFeedbackAPI: NativeMessageFeedbackAPI {}

/// Typed desktop-action boundary for settled Markdown file mentions. The Host
/// keeps both path opening authority and loopback/build-trust enforcement.
@MainActor
protocol NativeHostPathAPI: Sendable {
    func openPath(_ path: String) async throws -> HostOpenPathResponse
}

extension HostAPI: NativeHostPathAPI {}

/// Source: RC8 `resolveWorkspacePath`. This only constructs the Host-facing
/// spelling; it neither touches the local filesystem nor interprets a URL.
enum NativeProjectPathResolver {
    static func resolve(cwd: String?, path: String) -> String {
        guard !isAbsolute(path), let cwd, !cwd.isEmpty else { return path }
let base = trimmingTrailingSeparators(from: cwd)
        let relative = trimmingLeadingSeparators(from: path)
        return "\(base)/\(relative)"
    }

    private static func trimmingTrailingSeparators(from value: String) -> String {
        var end = value.endIndex
        while end > value.startIndex {
            let previous = value.index(before: end)
            guard value[previous] == "/" || value[previous] == "\\" else { break }
            end = previous
        }
        return String(value[..<end])
    }

    private static func trimmingLeadingSeparators(from value: String) -> String {
        var start = value.startIndex
        while start < value.endIndex {
            guard value[start] == "/" || value[start] == "\\" else { break }
            start = value.index(after: start)
        }
        return String(value[start...])
    }

    private static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\\\") { return true }
        let scalars = Array(path.unicodeScalars)
        return scalars.count >= 3
            && CharacterSet.letters.contains(scalars[0])
            && scalars[1].value == 58
            && (scalars[2].value == 47 || scalars[2].value == 92)
    }
}

/// Host-authoritative transcript state for the active native conversation.
///
/// Sources: `sessions.schema.ts:sessionHistoryValueSchema`,
/// `events.ts:MuxFrame`, and `chat-snapshot-builder.ts`. This initial native
/// reducer deliberately renders only official user/assistant text surfaces;
/// tool cards, images, approvals, queue and plugin surfaces remain owned by
/// their dedicated adapters rather than being guessed here.
@MainActor
final class NativeSessionStore: ObservableObject {
    /// Shared codecs for the per-frame JSON round-trip in `decode(_:from:)` and
    /// `prettyContent(in:)`. The store is @MainActor-isolated, so reuse is safe
    /// and avoids allocating two codecs per streamed frame.
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    enum Phase: Equatable {
        case idle
        case loading(sessionID: String)
        case ready(sessionID: String)
        case failed(sessionID: String)
    }

    /// RC8 `ui-model-selection` lifecycle. The directory itself remains an
    /// immutable Host response; this state records only the local request phase
    /// and its transient transport/business diagnostic.
    enum ModelDirectoryStatus: Equatable {
        case idle
        case loading
        case ready
        case selecting
        case error(String)
    }

    /// The only error shape the RC8 GoalBar displays inline: Host-provided
    /// business message plus code. Transport failures stay on the existing
    /// session recovery path and never gain invented goal-specific wording.
    /// Catalog-addressed child route retained while the child is selected. It is
    /// not inferred from session summaries and exists only for a valid Host row.
    struct SubagentRoute: Equatable {
        enum Mode: Equatable { case oneShot, continuable }
        let parentSessionID: String
        let childSessionID: String
        let mode: Mode
        let parentAvailable: Bool
    }

    struct GoalActionFailure: Equatable {
        let message: String
        let code: String
    }

    /// QueueDock catches an operation failure and delegates its visible text to
    /// the locale seat. The Core stores no invented network error string.
    struct QueueActionFailure: Equatable {
        enum Kind: Equatable {
            case edit
            case remove
            case steer
        }
        let itemID: String
        let kind: Kind
    }

    /// A successful queue RPC permits the view-local editor to close. It does
    /// not grant authority to remove or edit a Host snapshot row.
    struct QueueActionCompletion: Equatable {
        let itemID: String
        let action: SessionQueueAction
    }

    enum Role: Equatable {
        case user
        case assistant
    }

    struct TranscriptItem: Identifiable, Equatable {
        let id: String
        let role: Role
        var text: String
        var isStreaming: Bool
        /// Unix epoch milliseconds from the durable Host event. Snapshot-only
        /// fixtures may omit it; the UI then honestly hides clock chrome.
        let time: Double?
        let sequence: Int

        init(
            id: String,
            role: Role,
            text: String,
            isStreaming: Bool,
            time: Double? = nil,
            sequence: Int
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.isStreaming = isStreaming
            self.time = time
            self.sequence = sequence
        }
    }

    /// Source: `sessions.schema.ts:promptContentPartSchema`. This is transient
    /// composer state only; durable attachment identities remain Host-owned.
    struct PendingImage: Identifiable {
        let id: UUID
        let name: String
        let mediaType: String
        let data: Data
    }

    /// Source: `SessionEventMap['tool/call'|'tool/result']`. This generic native
    /// model preserves raw Host fields and optional view carrier without guessing
    /// a plugin-specific card schema.
    /// RC1 approval waterfall projected from `$events`. `eventID` is the
    /// answerable correlation identity; legacy `approvalID` remains optional
    /// only while the old SSE fallback is still compiled.
    struct PendingApproval: Identifiable, Equatable {
        let eventID: String
        let sessionID: String
        let approvalID: String?
        let toolName: String
        let callID: String?
        let reason: String?

        var id: String { eventID }
        var rpcID: String { eventID }

        init(
            eventID: String,
            sessionID: String,
            approvalID: String? = nil,
            toolName: String,
            callID: String?,
            reason: String?
        ) {
            self.eventID = eventID
            self.sessionID = sessionID
            self.approvalID = approvalID
            self.toolName = toolName
            self.callID = callID
            self.reason = reason
        }

        init(
            rpcID: String,
            sessionID: String,
            approvalID: String,
            toolName: String,
            callID: String?,
            reason: String?
        ) {
            self.init(
                eventID: rpcID,
                sessionID: sessionID,
                approvalID: approvalID,
                toolName: toolName,
                callID: callID,
                reason: reason
            )
        }
    }

    /// Source: `events.schema.ts:askUserQuestionItemSchema`.
    struct PendingQuestion: Identifiable, Equatable {
        struct Option: Identifiable, Equatable {
            let label: String
            let detail: String?
            var id: String { label }
        }

        struct Item: Identifiable, Equatable {
            enum Intent: Equatable {
                case planReview(approve: String)
            }

            let id: String
            let question: String
            let header: String?
            let detail: String?
            let options: [Option]
            let multiSelect: Bool
            /// Optional official presentation intent. Unknown wire tags reject
            /// the entire question request rather than falling back to an
            /// invented generic interaction.
            let intent: Intent?

            init(
                id: String,
                question: String,
                header: String?,
                detail: String?,
                options: [Option],
                multiSelect: Bool,
                intent: Intent? = nil
            ) {
                self.id = id
                self.question = question
                self.header = header
                self.detail = detail
                self.options = options
                self.multiSelect = multiSelect
                self.intent = intent
            }
        }

        let eventID: String
        let sessionID: String
        let items: [Item]

        var id: String { eventID }
        var rpcID: String { eventID }

        init(eventID: String, sessionID: String, items: [Item]) {
            self.eventID = eventID
            self.sessionID = sessionID
            self.items = items
        }

        init(rpcID: String, sessionID: String, items: [Item]) {
            self.init(eventID: rpcID, sessionID: sessionID, items: items)
        }
    }

    /// Source: `dsh-user-questions/types:QuestionAnswer`.
    struct QuestionAnswer: Equatable, Sendable {
        let id: String
        let selected: [String]
        let custom: String?
    }

    struct ToolInvocation: Identifiable {
        enum State: Equatable {
            case running
            case completed
            case failed
            case stopped
        }

        let id: String
        let name: String
        let arguments: String
        var output: String?
        /// Text-only result flatten used by rc.2 search-card recovery when a
        /// typed search result is truncated. Unlike `output`, it never includes
        /// non-text pretty JSON or an error fallback.
        var textOutput: String?
        /// Structured result error is retained for the rc.2 `resultText` empty
        /// fallback (`name: code`); it is not synthesized from transport state.
        var errorName: String?
        var errorCode: String?
        var state: State
        let sequence: Int
        /// The Host presents call and settled-result sides independently. They
        /// cannot share one field: a terminal result needs both views, while a
        /// terminal call followed by a generic result must take the raw generic
        /// fallback rather than inherit the earlier terminal card.
        var callView: ToolEventViewDTO?
        var resultView: ToolEventViewDTO?
    }

    /// Host `session/queue` whole-snapshot row. It is transient and therefore
    /// never reconstructed by folding durable history events.
    struct QueuedMessage: Identifiable, Equatable {
        enum Placement: String, Equatable {
            case queued
            case steering
            case context
        }

        let id: String
        let messageID: String
        let placement: Placement
        let role: String?
        let content: [JSONValue]
        let source: JSONValue?
        let preview: String
        let text: String?
    }

    /// Host `session/jobs` whole-snapshot row. A plugin-defined `kind` remains
    /// open while status stays within the locked wire contract.
    struct BackgroundJob: Identifiable, Equatable {
        enum Status: String, Equatable {
            case running
            case stopping
            case completed
            case killed
            case failed
        }

        let id: String
        let kind: String
        let label: String
        let status: Status
        let detail: String?
        let startedAt: Int
        let finishedAt: Int?

        var isLive: Bool { status == .running || status == .stopping }
    }

    /// Resident client window for one Host session. Durable transcript data is
    /// refreshed from history on re-selection; transient queue/jobs are retained
    /// only until the next `session/subscribed` generation baseline clears them.
    private struct ResidentSessionState {
        let items: [TranscriptItem]
        let hasMoreHistory: Bool
        let isRunning: Bool
        let selectedViewID: String?
        let draft: String
        let pendingImages: [PendingImage]
        let toolInvocations: [ToolInvocation]
        let queuedMessages: [QueuedMessage]
        let backgroundJobs: [BackgroundJob]
        let modelDirectory: CoreSessionModelDirectory?
        let selectedToolCallID: String?
        let pendingApproval: PendingApproval?
        let pendingQuestion: PendingQuestion?
        let lastError: DSHTransportError?
        /// Resident copies preserve the exact target-scoped keyed projection
        /// exposed before a temporary session switch. `conversationWindow`
        /// remains alongside them so a restored reducer can accept later Host
        /// history/mux inputs without replaying a UI-owned timeline.
        let chatNodes: [ConversationViewNode]
        let trajectoryNodes: [ConversationViewNode]
        let appliedSequences: Set<Int>
        let conversationWindow: [ConversationEventInput]
        let conversationHasMoreHistory: Bool
    }

    @Published private(set) var phase: Phase = .idle
    /// Compatibility projection retained while individual downstream surfaces
    /// complete their node-snapshot migration. Chat rendering reads `chatNodes`.
    @Published private(set) var items: [TranscriptItem] = []
    /// The stable keyed RC8 Chat target snapshot. It is materialized solely by
    /// `conversationReducer` from Host history/mux evidence.
    @Published private(set) var chatNodes: [ConversationViewNode] = []
    /// RC8 `conversation.view` trajectory target, materialized from the same
    /// authoritative reducer window as Chat but with target-owned node keys.
    @Published private(set) var trajectoryNodes: [ConversationViewNode] = []
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var isLoadingOlderHistory = false
    @Published private(set) var isRunning = false
    /// RC8 `ChatStoreState.view`: a retained id may be stale after a plugin
    /// unload, so UI resolves it through the stable Chat fallback.
    @Published private(set) var selectedViewID: String?
    @Published private(set) var isSubmittingPrompt = false
    @Published var draft = ""
    @Published private(set) var pendingImages: [PendingImage] = []
    /// Last Core-owned image admission decision. It is intentionally transient:
    /// presentation maps this safe category to locked official copy and never
    /// exposes file paths, decoded metadata, or transport-private errors.
    @Published private(set) var imageAdmissionRejection: NativeImageAttachmentAdmission.Rejection?
    @Published private(set) var toolInvocations: [ToolInvocation] = []
    @Published private(set) var queuedMessages: [QueuedMessage] = []
    @Published private(set) var backgroundJobs: [BackgroundJob] = []
    /// The per-session Host `session.models` authority. A nil value means it has
    /// not been loaded or the current session cannot be restored yet; it is not
    /// an invitation to invent a default provider/model pair.
    @Published private(set) var modelDirectory: CoreSessionModelDirectory?
    @Published private(set) var modelDirectoryStatus: ModelDirectoryStatus = .idle
    @Published private(set) var isSelectingModel = false

    /// A loaded non-routable directory is an explicit Host refusal to accept a
    /// composer prompt. Absence remains unknown/loading rather than a locally
    /// invented default route, preserving cold-open compatibility until the
    /// Host supplies `session.models` authority.
    var isPromptRouteAvailable: Bool { modelDirectory?.routable ?? true }
    @Published private(set) var isSubmittingPermission = false
    @Published private(set) var selectedToolCallID: String?
    @Published private(set) var pendingApproval: PendingApproval?
    @Published private(set) var pendingQuestion: PendingQuestion?
    @Published private(set) var subagentCatalog: SubagentListResponse?
    /// Complete Host catalogs keyed by their direct parent. The root current
    /// session remains exposed above for existing header consumers.
    @Published private(set) var subagentCatalogs: [String: SubagentListResponse] = [:]
    @Published private(set) var subagentRoute: SubagentRoute?
    /// Complete RC8 message-feedback sidecar snapshot keyed by assistant message id.
    /// A missing API or failed load remains empty; no local rating is invented.
    @Published private(set) var messageFeedbackItems: [String: MessageFeedbackItemDTO] = [:]
    @Published private(set) var isLoadingMessageFeedback = false
    @Published private(set) var isMessageFeedbackAvailable = false
    @Published private(set) var failedMessageFeedbackLoad = false
    @Published private(set) var isSubmittingMessageFeedback = false
    @Published private(set) var messageFeedbackActionFailureCode: String?
    @Published private(set) var messageFeedbackMutationMessageID: String?
    @Published private(set) var isLoadingSubagentCatalog = false
    @Published private(set) var loadingSubagentCatalogIDs: Set<String> = []
    /// Parent IDs whose last complete Host catalog request failed. This exposes
    /// retry eligibility without retaining transport-private error wording.
    @Published private(set) var failedSubagentCatalogIDs: Set<String> = []
    @Published private(set) var isSubmittingApproval = false
    @Published private(set) var isSubmittingQuestion = false
    @Published private(set) var lastError: DSHTransportError?
    @Published var promptSubmitError: String?
    @Published var historyLoadError: String?
    @Published var cancelAttemptError: String?

    /// Per-session Host-computed projections. UI reads completed values only;
    /// reducer-owned event folding never substitutes for this store.
    let projections = SessionProjectionStore()

    /// One typed read-only adapter over all extension surfaces attached to the
    /// active session. Durable conversation nodes and transient mux projections
    /// stay separated at their authority boundary; consumers never reconstruct
    /// queue, jobs, approval, question, todo, or goal state from raw events.
    var extensionState: CoreSessionExtensionState? {
        guard let activeSessionID else { return nil }
        return .init(
            projections: projections,
            sessionID: activeSessionID,
            modelDirectory: modelDirectory,
            queuedMessages: queuedMessages,
            backgroundJobs: backgroundJobs,
            pendingApproval: pendingApproval,
            pendingQuestion: pendingQuestion
        )
    }

    private var historyTask: Task<Void, Never>?
    private var sessionRuntime: SessionRuntime?
    private var sessionControlRuntime: SessionControlRuntime?
    private var remoteEventRuntime: RemoteEventRuntime?
    private var remoteInteractionTask: Task<Void, Never>?
    private var remoteInteractionBindingGeneration: UInt = 0
    private var sessionCommandService: SessionCommandService?
    private var sessionController: (any SessionControllerAPI)?
    private var remoteModelCatalog: RemoteModelCatalog?
    private var controlTask: Task<Void, Never>?
    private var controlBindingGeneration: UInt = 0
    private var promptTask: Task<Void, Never>?
    private var cancelTask: Task<Void, Never>?
    private var olderHistoryTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    /// A recovery is distinct from initial history loading. Its monotonic token
    /// prevents an old Host generation, endpoint, or selected session from
    /// applying models/history/projections after a newer authority request.
    private var recoveryTask: Task<Void, Never>?
    private var recoveryGeneration: UInt = 0
    /// RC8 `Session.liveBuffer` equivalent. While a full authority recovery is
    /// rebuilding the history window, live frames must wait to be stitched on
    /// top of that cut rather than being discarded or folded into an old window.
    private var recoveryLiveBuffer: [SessionHistoryEntryDTO] = []
    private var recoveryBufferGeneration: UInt?
    /// RC8 retains the mux subscription tail even when it arrives before the
    /// initial history page. Once that page lands, a mismatch triggers the
    /// second authority pull required to avoid a cold-to-live discontinuity.
    private var subscribedLastSequence: Int?
    private var endpoint: URL?
    private var api: (any NativeSessionAPI)?
    private var goalAPI: (any NativeGoalAPI)?
    private var subagentCatalogAPI: (any NativeSubagentCatalogAPI)?
    private var subagentContinuationAPI: (any NativeSubagentContinuationAPI)?
    private var messageFeedbackAPI: (any NativeMessageFeedbackAPI)?
    private var messageFeedbackTask: Task<Void, Never>?
    /// RC8 reconnect resync waits behind any admitted feedback mutation before
    /// taking a fresh complete list, so an older list cannot revive a stale CAS
    /// version after a mutation result has committed.
    private var messageFeedbackResyncTask: Task<Void, Never>?
    private var messageFeedbackMutationTask: Task<Void, Never>?
    /// Feedback mutations survive a same-session authority recovery so RC8
    /// reconnect resync can serialize behind their committed Host version. Only
    /// a session lifecycle change invalidates these writes.
    private var messageFeedbackSessionGeneration: UInt = 0
    private var messageFeedbackMutationGeneration: UInt = 0
    private var hasLoadedMessageFeedback = false
    private var subagentCatalogTask: Task<Void, Never>?
    private var subagentCatalogTasks: [String: Task<Void, Never>] = [:]
    private var goalTask: Task<Void, Never>?
    private var queueUpdateTask: Task<Void, Never>?
    private var modelSelectionTask: Task<Void, Never>?
    /// One RC8 directory generation spans models reloads and selections. A late
    /// open/recovery response may never overwrite a newer reload or selection.
    private var modelDirectoryGeneration: UInt = 0
    private var modelSelectionGeneration: UInt = 0
    private var permissionSelectionTask: Task<Void, Never>?
    private var permissionSelectionGeneration: UInt = 0
    /// Every takeover write is owned by the current pending interaction and is
    /// cancelled when its request, session, or mux generation is replaced.
    private var approvalSubmissionTask: Task<Void, Never>?
    private var questionSubmissionTask: Task<Void, Never>?
    /// Approval/question requests are scoped to a mux generation. A replayed
    /// request may reuse the same RPC id after Host restart, while an already
    /// admitted old response must still reach the Host without clearing the new
    /// wait's busy indicator.
    private var interactionGeneration: UInt = 0
    @Published private(set) var isSubmittingGoal = false
    @Published private(set) var goalActionFailure: GoalActionFailure?
    /// RC8 GoalBar hides a successfully cleared goal before the next whole
    /// projection arrives. This is a view marker only; `extensionState.goal`
    /// remains Host-owned and unchanged.
    @Published private(set) var locallyClearedGoalID: String?
    @Published private(set) var updatingQueueItemID: String?
    @Published private(set) var queueActionFailure: QueueActionFailure?
    @Published private(set) var queueActionCompletion: QueueActionCompletion?
    private var hostPathAPI: (any NativeHostPathAPI)?
    private var activeSessionCWD: String?
    private var activeSessionID: String?
    private var residentStates: [String: ResidentSessionState] = [:]
    private var appliedSequences: Set<Int> = []
    private var conversationReducer = ConversationNodeReducer(
        definitions: ConversationCoreNodeRegistry.initialDefinitions()
    )

    /// The shell uses this only to replay an existing selection against a new
    /// verified endpoint after Host recovery; the Host remains session truth.
    var selectedSessionID: String? { activeSessionID }

    /// RC8 `selectProducedFiles` counterpart. The state-only deliverables node
    /// stays in reducer-owned turn location data; this read-only seam applies
    /// its official closing-assistant cut before a native turn-tail renderer
    /// receives paths. It never parses raw history or creates local artifacts.
    func deliverables(forClosingAssistant assistant: CoreAssistantNode) -> [String] {
        conversationReducer
            .locationData(scope: .turn, turn: assistant.turn)
            .value(for: "deliverables", as: CoreDeliverablesTurnData.self)?
            .paths(forClosingSequence: assistant.seq) ?? []
    }

    func bindCommandService(_ service: SessionCommandService?) {
        sessionCommandService = service
    }

    func bindSessionController(_ controller: (any SessionControllerAPI)?) {
        sessionController = controller
        remoteModelCatalog = nil
    }

    func bindEventRuntime(_ runtime: RemoteEventRuntime?) {
        remoteInteractionTask?.cancel()
        remoteInteractionTask = nil
        remoteEventRuntime = runtime
        remoteInteractionBindingGeneration &+= 1
        let generation = remoteInteractionBindingGeneration
        guard let runtime else { return }
        remoteInteractionTask = Task { [weak self] in
            let interactions = await runtime.interactions()
            for await interaction in interactions {
                guard !Task.isCancelled,
                      self?.remoteInteractionBindingGeneration == generation
                else { return }
                self?.applyRemoteInteraction(interaction)
            }
        }
    }

    private func applyRemoteInteraction(_ update: RemoteSessionInteractionUpdate) {
        switch update {
        case let .approval(approval):
            guard approval.sessionID == activeSessionID else { return }
            invalidateInteractions()
            pendingApproval = PendingApproval(
                eventID: approval.eventID,
                sessionID: approval.sessionID,
                toolName: approval.toolName,
                callID: approval.callID,
                reason: approval.reason
            )
        case let .question(question):
            guard question.sessionID == activeSessionID else { return }
            invalidateInteractions()
            pendingQuestion = PendingQuestion(
                eventID: question.eventID,
                sessionID: question.sessionID,
                items: question.questions.map { item in
                    PendingQuestion.Item(
                        id: item.id,
                        question: item.question,
                        header: item.header,
                        detail: item.detail,
                        options: item.options.map { .init(label: $0.label, detail: $0.description) },
                        multiSelect: item.multiSelect,
                        intent: item.intent.map { intent in
                            switch intent {
                            case let .planReview(approve): return .planReview(approve: approve)
                            }
                        }
                    )
                }
            )
        case let .cancelled(eventID):
            if pendingApproval?.eventID == eventID {
                pendingApproval = nil
                invalidateApprovalSubmission()
            }
            if pendingQuestion?.eventID == eventID {
                pendingQuestion = nil
                invalidateQuestionSubmission()
            }
        }
    }

    func bindControlRuntime(_ runtime: SessionControlRuntime?) {
        controlTask?.cancel()
        controlTask = nil
        sessionControlRuntime = runtime
        controlBindingGeneration &+= 1
        let generation = controlBindingGeneration
        guard let runtime else {
            queuedMessages = []
            backgroundJobs = []
            return
        }
        controlTask = Task { [weak self] in
            do {
                let opening = try await runtime.open()
                guard !Task.isCancelled, self?.controlBindingGeneration == generation else { return }
                self?.installRemoteControl(opening)
                let snapshots = await runtime.snapshots()
                for await snapshot in snapshots {
                    guard !Task.isCancelled, self?.controlBindingGeneration == generation else { return }
                    guard let snapshot else {
                        self?.queuedMessages = []
                        self?.backgroundJobs = []
                        continue
                    }
                    self?.installRemoteControl(snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self?.controlBindingGeneration == generation else { return }
                self?.queuedMessages = []
                self?.backgroundJobs = []
            }
        }
    }

    /// Core-internal test seam for queue mutation fencing. Production receives
    /// the same API from `NativeShellPresentation.connectVerifiedHost` via `open`.
    func setSessionAPIForTesting(_ api: (any NativeSessionAPI)?) {
        queueUpdateTask?.cancel()
        queueUpdateTask = nil
        modelSelectionTask?.cancel()
        modelSelectionTask = nil
        modelDirectoryGeneration &+= 1
        modelSelectionGeneration &+= 1
        isSelectingModel = false
        modelDirectoryStatus = modelDirectory == nil ? .idle : .ready
        permissionSelectionTask?.cancel()
        permissionSelectionTask = nil
        permissionSelectionGeneration &+= 1
        isSubmittingPermission = false
        updatingQueueItemID = nil
        queueActionFailure = nil
        queueActionCompletion = nil
        self.api = api
    }

    /// Core-internal test seam for goal mutation fencing. Production receives the
    /// same API from `NativeShellPresentation.connectVerifiedHost` via `open`.
    /// Accepts the selected catalog row as the only route source. Invalid or
    /// diagnostic rows fail closed rather than enabling continuation by ID.
    func setSubagentRoute(parentSessionID: String, entry: SubagentListEntryDTO, parentAvailable: Bool) {
        let mode: SubagentRoute.Mode?
        switch entry.mode {
        case "one-shot": mode = .oneShot
        case "continuable": mode = .continuable
        default: mode = nil
        }
        guard entry.kind == "child", let mode else {
            subagentRoute = nil
            return
        }
        subagentRoute = .init(parentSessionID: parentSessionID, childSessionID: entry.id, mode: mode, parentAvailable: parentAvailable)
    }

    /// Core test seam; production injects the same verified Host facade through `open`.
    func setMessageFeedbackAPIForTesting(_ api: (any NativeMessageFeedbackAPI)?) {
        messageFeedbackTask?.cancel()
        messageFeedbackTask = nil
        messageFeedbackResyncTask?.cancel()
        messageFeedbackResyncTask = nil
        messageFeedbackSessionGeneration &+= 1
        messageFeedbackItems = [:]
        isLoadingMessageFeedback = false
        failedMessageFeedbackLoad = false
        isSubmittingMessageFeedback = false
        messageFeedbackActionFailureCode = nil
        messageFeedbackMutationMessageID = nil
        hasLoadedMessageFeedback = false
        isMessageFeedbackAvailable = api != nil
        messageFeedbackAPI = api
    }

    /// Fetches a complete sidecar snapshot. A business or carrier failure clears
    /// visible feedback rather than retaining stale ratings from another session.
    func refreshMessageFeedback() {
        guard let api = messageFeedbackAPI, let sessionID = activeSessionID else {
            messageFeedbackItems = [:]
            return
        }
        messageFeedbackTask?.cancel()
        let generation = recoveryGeneration
        isLoadingMessageFeedback = true
        failedMessageFeedbackLoad = false
        messageFeedbackTask = Task { [weak self] in
            defer {
                if self?.recoveryGeneration == generation, self?.activeSessionID == sessionID {
                    self?.isLoadingMessageFeedback = false
                    self?.messageFeedbackTask = nil
                }
            }
            do {
                let response = try await api.list(sessionID: sessionID)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.activeSessionID == sessionID
                else { return }
                guard response.ok, let items = response.value?.items else {
                    self?.messageFeedbackItems = [:]
                    self?.hasLoadedMessageFeedback = false
                    self?.failedMessageFeedbackLoad = true
                    return
                }
                self?.messageFeedbackItems = Dictionary(uniqueKeysWithValues: items.map { ($0.messageId, $0) })
                self?.hasLoadedMessageFeedback = true
            } catch {
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.activeSessionID == sessionID
                else { return }
                self?.messageFeedbackItems = [:]
                self?.hasLoadedMessageFeedback = false
                self?.failedMessageFeedbackLoad = true
            }
        }
    }

    /// RC8 `SessionManager.handleConnected`: refresh the selected parent plus
    /// every catalog already being observed. The native header owns disclosure
    /// state, so this Store treats its keyed complete Host snapshots as the only
    /// durable observation set; it never derives descriptors from summaries.
    private func resyncSubagentCatalogsAfterRecovery() {
        guard let rootSessionID = activeSessionID, subagentCatalogAPI != nil else { return }
        let selectedAddressParent = subagentRoute?.childSessionID == rootSessionID
            ? subagentRoute?.parentSessionID
            : nil
        let observedParents = Set(subagentCatalogs.keys)
            .union([rootSessionID])
            .union(selectedAddressParent.map { [$0] } ?? [])
        for parentSessionID in observedParents {
            refreshSubagentCatalog(parentSessionID: parentSessionID)
        }
    }

    /// RC8 `MessageFeedbackController.resync`: serialize the reconnect list
    /// behind the prior mutation tail. The completed Host list remains the only
    /// source that replaces the sidecar; no local version is synthesized.
    private func resyncMessageFeedbackAfterRecovery() {
        guard messageFeedbackAPI != nil, let sessionID = activeSessionID else { return }
        messageFeedbackResyncTask?.cancel()
        let generation = recoveryGeneration
        let priorMutation = messageFeedbackMutationTask
        messageFeedbackResyncTask = Task { [weak self] in
            if let priorMutation { await priorMutation.value }
            guard !Task.isCancelled,
                  self?.recoveryGeneration == generation,
                  self?.activeSessionID == sessionID
            else { return }
            self?.refreshMessageFeedback()
            if let loading = self?.messageFeedbackTask { await loading.value }
            guard !Task.isCancelled,
                  self?.recoveryGeneration == generation,
                  self?.activeSessionID == sessionID
            else { return }
            self?.messageFeedbackResyncTask = nil
        }
    }

    private enum MessageFeedbackAction {
        case toggle(messageID: String, rating: MessageFeedbackRatingDTO)
        case rate(messageID: String, rating: MessageFeedbackRatingDTO, note: String?)
        case clear(messageID: String)

        var messageID: String {
            switch self {
            case let .toggle(messageID, _), let .rate(messageID, _, _), let .clear(messageID):
                return messageID
            }
        }
    }

    /// RC8 toggle behavior: matching committed rating retracts it; another rating
    /// replaces it while preserving the Host-owned note. No state is optimistic.
    func toggleMessageFeedback(messageID: String, rating: MessageFeedbackRatingDTO) {
        enqueueMessageFeedbackMutation(.toggle(messageID: messageID, rating: rating))
    }

    func clearMessageFeedback(messageID: String) {
        enqueueMessageFeedbackMutation(.clear(messageID: messageID))
    }

    /// RC8 note editor only saves against an already committed rating. An empty
    /// draft is a deliberate `note: nil` clear, not an invented no-op.
    func saveMessageFeedbackNote(messageID: String, note: String) {
        guard let item = messageFeedbackItems[messageID] else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        enqueueMessageFeedbackMutation(.rate(messageID: messageID, rating: item.rating, note: trimmed.isEmpty ? nil : trimmed))
    }

    private func enqueueMessageFeedbackMutation(_ action: MessageFeedbackAction) {
        guard let api = messageFeedbackAPI, let sessionID = activeSessionID else { return }
        let generation = messageFeedbackSessionGeneration
        let actionMessageID = action.messageID
        messageFeedbackMutationGeneration &+= 1
        let mutationGeneration = messageFeedbackMutationGeneration
        let previous = messageFeedbackMutationTask
        isSubmittingMessageFeedback = true
        messageFeedbackActionFailureCode = nil
        messageFeedbackMutationMessageID = actionMessageID
        messageFeedbackMutationTask = Task { [weak self] in
            if let previous { await previous.value }
            guard !Task.isCancelled,
                  self?.messageFeedbackSessionGeneration == generation,
                  self?.activeSessionID == sessionID
            else { return }

            if self?.hasLoadedMessageFeedback != true {
                if self?.isLoadingMessageFeedback == true {
                    if let loading = self?.messageFeedbackTask { await loading.value }
                } else {
                    self?.refreshMessageFeedback()
                    if let loading = self?.messageFeedbackTask { await loading.value }
                }
            }
            guard !Task.isCancelled,
                  self?.messageFeedbackSessionGeneration == generation,
                  self?.activeSessionID == sessionID,
                  self?.hasLoadedMessageFeedback == true
            else {
                self?.settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: "transport")
                return
            }

            let messageID: String
            let observed: MessageFeedbackItemDTO?
            switch action {
            case let .toggle(id, _), let .rate(id, _, _), let .clear(id):
                messageID = id
                observed = self?.messageFeedbackItems[id]
            }
            do {
                switch action {
                case let .toggle(_, rating):
                    if observed?.rating == rating, let observed {
                        let response = try await api.delete(.init(sessionId: sessionID, messageId: messageID, ifVersion: observed.version))
                        self?.applyMessageFeedbackDelete(response, messageID: messageID, generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration)
                    } else {
                        let response = try await api.put(.init(
                            sessionId: sessionID,
                            messageId: messageID,
                            rating: rating,
                            note: observed?.note,
                            ifVersion: observed?.version
                        ))
                        self?.applyMessageFeedbackPut(response, messageID: messageID, generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration)
                    }
                case let .rate(_, rating, note):
                    guard let observed else {
                        self?.settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: nil)
                        return
                    }
                    let response = try await api.put(.init(
                        sessionId: sessionID,
                        messageId: messageID,
                        rating: rating,
                        note: note,
                        ifVersion: observed.version
                    ))
                    self?.applyMessageFeedbackPut(response, messageID: messageID, generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration)
                case .clear:
                    guard let observed else {
                        self?.settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: nil)
                        return
                    }
                    let response = try await api.delete(.init(sessionId: sessionID, messageId: messageID, ifVersion: observed.version))
                    self?.applyMessageFeedbackDelete(response, messageID: messageID, generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration)
                }
            } catch {
                self?.settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: "transport")
            }
        }
    }

    private func applyMessageFeedbackPut(
        _ response: MessageFeedbackPutResponse,
        messageID: String,
        generation: UInt,
        sessionID: String,
        mutationGeneration: UInt
    ) {
        guard messageFeedbackSessionGeneration == generation, activeSessionID == sessionID else { return }
        if response.ok, let item = response.value {
            messageFeedbackItems[messageID] = item
            settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: nil)
            return
        }
        if response.error?.code == "version-conflict" {
            commitMessageFeedbackCurrent(response.error?.current, messageID: messageID)
        }
        settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: response.error?.code ?? "transport")
    }

    private func applyMessageFeedbackDelete(
        _ response: MessageFeedbackDeleteResponse,
        messageID: String,
        generation: UInt,
        sessionID: String,
        mutationGeneration: UInt
    ) {
        guard recoveryGeneration == generation, activeSessionID == sessionID else { return }
        if response.ok, response.value?.absent == true {
            messageFeedbackItems[messageID] = nil
            settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: nil)
            return
        }
        if response.error?.code == "version-conflict" {
            commitMessageFeedbackCurrent(response.error?.current, messageID: messageID)
        }
        settleMessageFeedbackMutation(generation: generation, sessionID: sessionID, mutationGeneration: mutationGeneration, failureCode: response.error?.code ?? "transport")
    }

    private func commitMessageFeedbackCurrent(_ current: MessageFeedbackItemDTO?, messageID: String) {
        messageFeedbackItems[messageID] = current
    }

    private func settleMessageFeedbackMutation(generation: UInt, sessionID: String, mutationGeneration: UInt, failureCode: String?) {
        guard messageFeedbackSessionGeneration == generation,
              activeSessionID == sessionID,
              messageFeedbackMutationGeneration == mutationGeneration
        else { return }
        isSubmittingMessageFeedback = false
        messageFeedbackActionFailureCode = failureCode
        if failureCode == nil { messageFeedbackMutationMessageID = nil }
        messageFeedbackMutationTask = nil
    }

    func setSubagentCatalogAPIForTesting(_ api: (any NativeSubagentCatalogAPI)?) {
        subagentCatalogTask?.cancel()
        subagentCatalogTasks.values.forEach { $0.cancel() }
        subagentCatalogTask = nil
        subagentCatalogTasks = [:]
        isLoadingSubagentCatalog = false
        loadingSubagentCatalogIDs = []
        failedSubagentCatalogIDs = []
        subagentCatalog = nil
        subagentCatalogs = [:]
        subagentCatalogAPI = api
    }

    /// Refreshes only the selected session's complete Host catalog. Failure is
    /// fail-closed: the caller observes no catalog rather than local descendants.
    func refreshSubagentCatalog() {
        guard let sessionID = activeSessionID else {
            subagentCatalog = nil
            return
        }
        refreshSubagentCatalog(parentSessionID: sessionID)
    }

    /// Explicit recursive catalog refresh. Each direct parent is keyed and
    /// fenced by the same selected-root generation; no summary-derived child
    /// may be inserted while a catalog request is pending or failed.
    func refreshSubagentCatalog(parentSessionID: String) {
        guard let api = subagentCatalogAPI, let rootSessionID = activeSessionID else { return }
        subagentCatalogTasks[parentSessionID]?.cancel()
        let generation = recoveryGeneration
        failedSubagentCatalogIDs.remove(parentSessionID)
        loadingSubagentCatalogIDs.insert(parentSessionID)
        if parentSessionID == rootSessionID { isLoadingSubagentCatalog = true }
        let task = Task { [weak self] in
            defer {
                if self?.recoveryGeneration == generation, self?.activeSessionID == rootSessionID {
                    self?.loadingSubagentCatalogIDs.remove(parentSessionID)
                    self?.subagentCatalogTasks[parentSessionID] = nil
                    if parentSessionID == rootSessionID { self?.isLoadingSubagentCatalog = false }
                }
            }
            do {
                let catalog = try await api.list(parentSessionID: parentSessionID)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.activeSessionID == rootSessionID
                else { return }
                self?.failedSubagentCatalogIDs.remove(parentSessionID)
                self?.subagentCatalogs[parentSessionID] = catalog
                if parentSessionID == rootSessionID { self?.subagentCatalog = catalog }
            } catch {
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.activeSessionID == rootSessionID
                else { return }
                self?.failedSubagentCatalogIDs.insert(parentSessionID)
                self?.subagentCatalogs[parentSessionID] = nil
                if parentSessionID == rootSessionID { self?.subagentCatalog = nil }
            }
        }
        subagentCatalogTasks[parentSessionID] = task
        if parentSessionID == rootSessionID { subagentCatalogTask = task }
    }

    func setGoalAPIForTesting(_ api: (any NativeGoalAPI)?) {
        goalTask?.cancel()
        goalTask = nil
        isSubmittingGoal = false
        goalActionFailure = nil
        locallyClearedGoalID = nil
        queueUpdateTask?.cancel()
        queueUpdateTask = nil
        modelSelectionTask?.cancel()
        modelSelectionTask = nil
        modelDirectoryGeneration &+= 1
        modelSelectionGeneration &+= 1
        isSelectingModel = false
        modelDirectoryStatus = modelDirectory == nil ? .idle : .ready
        permissionSelectionTask?.cancel()
        permissionSelectionTask = nil
        permissionSelectionGeneration &+= 1
        isSubmittingPermission = false
        updatingQueueItemID = nil
        queueActionFailure = nil
        queueActionCompletion = nil
        goalAPI = api
    }

    /// Source: RC8 `SessionProjectionMap.imageLimits`. Native clients admit
    /// image bytes only when the Host has supplied this complete contract; this
    /// fails closed rather than inventing a local size/type policy.
    var imageAttachmentLimits: ImageAttachmentLimits? {
        guard let sessionID = activeSessionID,
              let value = projections.value(sessionID: sessionID, key: "imageLimits")
        else { return nil }
        return decode(ImageAttachmentLimits.self, from: value)
    }

    deinit {
        historyTask?.cancel()
        olderHistoryTask?.cancel()
        promptTask?.cancel()
        cancelTask?.cancel()
        streamTask?.cancel()
        recoveryTask?.cancel()
        approvalSubmissionTask?.cancel()
        questionSubmissionTask?.cancel()
        remoteInteractionTask?.cancel()
        subagentCatalogTask?.cancel()
    }

    /// Core-internal reducer seam used by regression tests; Feature/UI enters
    /// through `open`, never by mutating session state directly.
    func preserveActiveState() {
        guard let sessionID = activeSessionID else { return }
        residentStates[sessionID] = ResidentSessionState(
            items: items,
            hasMoreHistory: hasMoreHistory,
            isRunning: isRunning,
            selectedViewID: selectedViewID,
            draft: draft,
            pendingImages: pendingImages,
            toolInvocations: toolInvocations,
            queuedMessages: queuedMessages,
            backgroundJobs: backgroundJobs,
            modelDirectory: modelDirectory,
            selectedToolCallID: selectedToolCallID,
            pendingApproval: pendingApproval,
            pendingQuestion: pendingQuestion,
            lastError: lastError,
            chatNodes: chatNodes,
            trajectoryNodes: trajectoryNodes,
            appliedSequences: appliedSequences,
            conversationWindow: conversationReducer.rawWindow(),
            conversationHasMoreHistory: conversationReducer.currentHasMoreHistory()
        )
    }

    /// Core-internal resident-window restore seam used by regression tests.
    @discardableResult
    func restoreResidentState(for sessionID: String) -> Bool {
        guard let state = residentStates[sessionID] else { return false }
        items = state.items
        hasMoreHistory = state.hasMoreHistory
        isLoadingOlderHistory = false
        isRunning = state.isRunning
        selectedViewID = state.selectedViewID
        isSubmittingPrompt = false
        draft = state.draft
        pendingImages = state.pendingImages
        toolInvocations = state.toolInvocations
        queuedMessages = state.queuedMessages
        backgroundJobs = state.backgroundJobs
        modelDirectory = state.modelDirectory
        selectedToolCallID = state.selectedToolCallID
        pendingApproval = state.pendingApproval
        pendingQuestion = state.pendingQuestion
        isSubmittingApproval = false
        isSubmittingQuestion = false
        lastError = state.lastError
        appliedSequences = state.appliedSequences
        replaceConversationWindow(state.conversationWindow, hasMore: state.conversationHasMoreHistory)
        // The reducer window is restored first for future Host input, then its
        // exact resident target snapshots are reinstated for immediate native
        // tab presentation. Both targets are snapshot-only UI projections.
        chatNodes = state.chatNodes
        trajectoryNodes = state.trajectoryNodes
        return true
    }

    /// Opens one selected Host session. Re-selecting a resident session restores
    /// its visible window synchronously, then refreshes the Host authority in the
    /// background; a cold session alone enters the blocking history phase.
    func open(
        sessionID: String,
        using api: any NativeSessionAPI,
        endpoint: URL,
        hostPathAPI: (any NativeHostPathAPI)? = nil,
        goalAPI: (any NativeGoalAPI)? = nil,
        subagentCatalogAPI: (any NativeSubagentCatalogAPI)? = nil,
        subagentContinuationAPI: (any NativeSubagentContinuationAPI)? = nil,
        messageFeedbackAPI: (any NativeMessageFeedbackAPI)? = nil,
        sessionCWD: String? = nil,
        sessionRuntime: SessionRuntime? = nil
    ) {
        guard activeSessionID != sessionID || self.endpoint != endpoint else { return }
        let selectedSubagentRoute = subagentRoute?.childSessionID == sessionID ? subagentRoute : nil
        preserveActiveState()
        let previousSessionRuntime = self.sessionRuntime
        self.sessionRuntime = sessionRuntime
        Task { await previousSessionRuntime?.close() }
        historyTask?.cancel()
        olderHistoryTask?.cancel()
        promptTask?.cancel()
        cancelTask?.cancel()
        streamTask?.cancel()
        recoveryTask?.cancel()
        recoveryLiveBuffer = []
        recoveryBufferGeneration = nil
        goalTask?.cancel()
        goalTask = nil
        subagentCatalogTask?.cancel()
        subagentCatalogTasks.values.forEach { $0.cancel() }
        subagentCatalogTask = nil
        subagentCatalogTasks = [:]
        messageFeedbackTask?.cancel()
        messageFeedbackTask = nil
        messageFeedbackResyncTask?.cancel()
        messageFeedbackResyncTask = nil
        messageFeedbackSessionGeneration &+= 1
        messageFeedbackMutationTask?.cancel()
        messageFeedbackMutationTask = nil
        messageFeedbackItems = [:]
        isLoadingMessageFeedback = false
        failedMessageFeedbackLoad = false
        isSubmittingMessageFeedback = false
        messageFeedbackActionFailureCode = nil
        messageFeedbackMutationMessageID = nil
        hasLoadedMessageFeedback = false
        subagentCatalog = nil
        subagentCatalogs = [:]
        subagentRoute = selectedSubagentRoute
        isLoadingSubagentCatalog = false
        loadingSubagentCatalogIDs = []
        failedSubagentCatalogIDs = []
        isSubmittingGoal = false
        goalActionFailure = nil
        locallyClearedGoalID = nil
        queueUpdateTask?.cancel()
        queueUpdateTask = nil
        modelSelectionTask?.cancel()
        modelSelectionTask = nil
        modelDirectoryGeneration &+= 1
        modelSelectionGeneration &+= 1
        isSelectingModel = false
        modelDirectoryStatus = modelDirectory == nil ? .idle : .ready
        permissionSelectionTask?.cancel()
        permissionSelectionTask = nil
        permissionSelectionGeneration &+= 1
        isSubmittingPermission = false
        updatingQueueItemID = nil
        queueActionFailure = nil
        queueActionCompletion = nil
        recoveryGeneration &+= 1
        invalidateInteractions()
        subscribedLastSequence = nil
        let authorityGeneration = recoveryGeneration
        // RC8 buffers live frames during the first authority read as well as
        // gap recovery. The common generation gate keeps a replaced session or
        // endpoint from stitching its old pending tail into the new window.
        recoveryBufferGeneration = authorityGeneration
        let directoryGeneration = modelDirectoryGeneration
        self.api = api
        self.goalAPI = goalAPI
        self.subagentCatalogAPI = subagentCatalogAPI
        self.subagentContinuationAPI = subagentContinuationAPI
        self.messageFeedbackAPI = messageFeedbackAPI
        self.isMessageFeedbackAvailable = messageFeedbackAPI != nil
        self.hostPathAPI = hostPathAPI
        self.activeSessionCWD = sessionCWD
        self.endpoint = endpoint
        activeSessionID = sessionID
        if let sessionControlRuntime {
            let controlGeneration = controlBindingGeneration
            Task { [weak self] in
                guard let snapshot = await sessionControlRuntime.currentSnapshot(),
                      !Task.isCancelled,
                      self?.controlBindingGeneration == controlGeneration,
                      self?.activeSessionID == sessionID
                else { return }
                self?.installRemoteControl(snapshot)
            }
        }
        if subagentRoute?.childSessionID != sessionID { subagentRoute = nil }
        refreshMessageFeedback()
        let restoredResident = restoreResidentState(for: sessionID)
        if !restoredResident {
            items = []
            resetConversationWindow()
            toolInvocations = []
            queuedMessages = []
            backgroundJobs = []
            modelDirectory = nil
            modelDirectoryStatus = .idle
            selectedToolCallID = nil
            pendingApproval = nil
            pendingQuestion = nil
            isSubmittingApproval = false
            isSubmittingQuestion = false
            appliedSequences = []
            hasMoreHistory = false
            isLoadingOlderHistory = false
            isRunning = false
            selectedViewID = nil
            isSubmittingPrompt = false
            draft = ""
            pendingImages = []
            lastError = nil
            phase = .loading(sessionID: sessionID)
        } else {
            // The render tree remains on the resident window while the next
            // history authority baseline arrives; this is not a new blank UI.
            phase = .ready(sessionID: sessionID)
        }

        modelDirectoryStatus = .loading
        historyTask = Task { [weak self] in
            do {
                if let sessionRuntime, let sessionController = self?.sessionController {
                    let catalog: RemoteModelCatalog
                    if let cached = self?.remoteModelCatalog {
                        catalog = cached
                    } else {
                        catalog = try await sessionController.modelCatalog()
                    }
                    guard !Task.isCancelled,
                          self?.recoveryGeneration == authorityGeneration,
                          self?.modelDirectoryGeneration == directoryGeneration,
                          self?.activeSessionID == sessionID,
                          self?.endpoint == endpoint
                    else { return }
                    self?.remoteModelCatalog = catalog

                    let opening = try await sessionRuntime.open()
                    guard !Task.isCancelled,
                          self?.recoveryGeneration == authorityGeneration,
                          self?.activeSessionID == sessionID,
                          self?.endpoint == endpoint
                    else { return }
                    self?.installRemoteJournal(opening, sessionID: sessionID)
                    self?.refreshRemoteModelDirectory(sessionID: sessionID)
                    self?.modelDirectoryStatus = .ready
                    self?.phase = .ready(sessionID: sessionID)
                    let snapshots = await sessionRuntime.snapshots()
                    for await snapshot in snapshots {
                        guard !Task.isCancelled,
                              self?.recoveryGeneration == authorityGeneration,
                              self?.activeSessionID == sessionID,
                              self?.endpoint == endpoint
                        else { return }
                        self?.installRemoteJournal(snapshot, sessionID: sessionID)
                    }
                    return
                }

                // Legacy/test fallback while the remaining facade-only domains
                // are cut over to rc.1 Remote.
                let models = try await api.models(sessionID: sessionID)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == authorityGeneration,
                      self?.modelDirectoryGeneration == directoryGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                self?.modelDirectory = .init(response: models)
                self?.modelDirectoryStatus = .ready

                let response = try await api.history(sessionID: sessionID, beforeSeq: nil, maxMessages: nil)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == authorityGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                self?.replaceConversationWindow(response.events.map(ConversationEventInput.init(entry:)), hasMore: response.hasMore)
                self?.applyHistory(response.events)
                if let projections = response.projections { self?.projections.seed(sessionID: sessionID, baseline: projections) }
                self?.hasMoreHistory = response.hasMore
                self?.phase = .ready(sessionID: sessionID)
                self?.stitchRecoveryLiveBuffer(generation: authorityGeneration)
                self?.observeMux(sessionID: sessionID, endpoint: endpoint)
                if self?.consumeSubscriptionTailMismatch() == true {
                    self?.requestAuthorityRecovery(sessionID: sessionID, reason: .subscriptionWatermark)
                }
            } catch let error as DSHTransportError {
                guard !Task.isCancelled,
                      self?.recoveryGeneration == authorityGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                self?.lastError = error
                if case .loading = self?.modelDirectoryStatus {
                    self?.modelDirectoryStatus = .error(error.localizedDescription)
                }
                if self?.recoveryBufferGeneration == authorityGeneration {
                    self?.recoveryBufferGeneration = nil
                    self?.recoveryLiveBuffer = []
                }
                if !restoredResident { self?.phase = .failed(sessionID: sessionID) }
            } catch {
                guard !Task.isCancelled,
                      self?.recoveryGeneration == authorityGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                if case .loading = self?.modelDirectoryStatus {
                    self?.modelDirectoryStatus = .error(error.localizedDescription)
                }
                if self?.recoveryBufferGeneration == authorityGeneration {
                    self?.recoveryBufferGeneration = nil
                    self?.recoveryLiveBuffer = []
                }
                if !restoredResident { self?.phase = .failed(sessionID: sessionID) }
            }
        }
    }

    /// Source: RC8 `sessions/service.ts:clear`. Clears only the active
    /// selection so a no-session shell can be shown; it deliberately retains
    /// resident snapshots for a later open and does not tear down the verified
    /// Host connection owned by the shell.
    func clearActiveSelection() {
        // Preserve the currently staged Host projection before clearing only
        // the selection. RC8 `sessions.clear()` does not evict that resident
        // view; a later open may restore it while fresh authority arrives.
        preserveActiveState()
        historyTask?.cancel()
        historyTask = nil
        let previousSessionRuntime = sessionRuntime
        sessionRuntime = nil
        Task { await previousSessionRuntime?.close() }
        olderHistoryTask?.cancel()
        olderHistoryTask = nil
        streamTask?.cancel()
        streamTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryGeneration &+= 1
        promptTask?.cancel()
        promptTask = nil
        invalidateInteractions()
        recoveryLiveBuffer = []
        recoveryBufferGeneration = nil
        subscribedLastSequence = nil
        messageFeedbackTask?.cancel()
        messageFeedbackTask = nil
        messageFeedbackResyncTask?.cancel()
        messageFeedbackResyncTask = nil
        messageFeedbackSessionGeneration &+= 1
        messageFeedbackMutationTask?.cancel()
        messageFeedbackMutationTask = nil
        messageFeedbackAPI = nil
        isMessageFeedbackAvailable = false
        messageFeedbackItems = [:]
        isLoadingMessageFeedback = false
        failedMessageFeedbackLoad = false
        isSubmittingMessageFeedback = false
        messageFeedbackActionFailureCode = nil
        messageFeedbackMutationMessageID = nil
        hasLoadedMessageFeedback = false
        endpoint = nil
        api = nil
        goalTask?.cancel()
        goalTask = nil
        goalAPI = nil
        isSubmittingGoal = false
        goalActionFailure = nil
        locallyClearedGoalID = nil
        queueUpdateTask?.cancel()
        queueUpdateTask = nil
        modelSelectionTask?.cancel()
        modelSelectionTask = nil
        modelDirectoryGeneration &+= 1
        modelSelectionGeneration &+= 1
        isSelectingModel = false
        modelDirectoryStatus = modelDirectory == nil ? .idle : .ready
        permissionSelectionTask?.cancel()
        permissionSelectionTask = nil
        permissionSelectionGeneration &+= 1
        isSubmittingPermission = false
        updatingQueueItemID = nil
        queueActionFailure = nil
        queueActionCompletion = nil
        hostPathAPI = nil
        activeSessionCWD = nil
        activeSessionID = nil
        phase = .idle
        items = []
        resetConversationWindow()
        toolInvocations = []
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
        modelDirectoryStatus = .idle
        selectedToolCallID = nil
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        appliedSequences = []
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isRunning = false
        selectedViewID = nil
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
    }

    func disconnect() {
        bindCommandService(nil)
        bindSessionController(nil)
        bindEventRuntime(nil)
        bindControlRuntime(nil)
        historyTask?.cancel()
        historyTask = nil
        let previousSessionRuntime = sessionRuntime
        sessionRuntime = nil
        Task { await previousSessionRuntime?.close() }
        olderHistoryTask?.cancel()
        olderHistoryTask = nil
        streamTask?.cancel()
        streamTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryGeneration &+= 1
        promptTask?.cancel()
        promptTask = nil
        invalidateInteractions()
        recoveryLiveBuffer = []
        recoveryBufferGeneration = nil
        subscribedLastSequence = nil
        messageFeedbackTask?.cancel()
        messageFeedbackTask = nil
        messageFeedbackResyncTask?.cancel()
        messageFeedbackResyncTask = nil
        messageFeedbackSessionGeneration &+= 1
        messageFeedbackMutationTask?.cancel()
        messageFeedbackMutationTask = nil
        messageFeedbackAPI = nil
        isMessageFeedbackAvailable = false
        messageFeedbackItems = [:]
        isLoadingMessageFeedback = false
        failedMessageFeedbackLoad = false
        isSubmittingMessageFeedback = false
        messageFeedbackActionFailureCode = nil
        messageFeedbackMutationMessageID = nil
        hasLoadedMessageFeedback = false
        endpoint = nil
        api = nil
        goalTask?.cancel()
        goalTask = nil
        goalAPI = nil
        isSubmittingGoal = false
        goalActionFailure = nil
        locallyClearedGoalID = nil
        queueUpdateTask?.cancel()
        queueUpdateTask = nil
        modelSelectionTask?.cancel()
        modelSelectionTask = nil
        modelDirectoryGeneration &+= 1
        modelSelectionGeneration &+= 1
        isSelectingModel = false
        modelDirectoryStatus = modelDirectory == nil ? .idle : .ready
        permissionSelectionTask?.cancel()
        permissionSelectionTask = nil
        permissionSelectionGeneration &+= 1
        isSubmittingPermission = false
        updatingQueueItemID = nil
        queueActionFailure = nil
        queueActionCompletion = nil
        hostPathAPI = nil
        activeSessionCWD = nil
        activeSessionID = nil
        phase = .idle
        items = []
        resetConversationWindow()
        toolInvocations = []
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
        modelDirectoryStatus = .idle
        selectedToolCallID = nil
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        appliedSequences = []
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isRunning = false
        selectedViewID = nil
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        residentStates.removeAll()
        projections.removeAll()
    }

    /// Selects a registry-owned conversation view id. The store intentionally
    /// retains unknown ids so the UI can exercise RC8's stable Chat fallback
    /// without erasing persisted state on a transient plugin unload.
    func selectView(_ id: String?) {
        selectedViewID = id
    }

    func addPendingImage(_ url: URL) {
        let admission = NativeImageAttachmentAdmission.admit(
            url: url,
            limits: imageAttachmentLimits,
            existingImageCount: pendingImages.count,
            existingImageBytes: pendingImages.reduce(into: 0) { partial, image in
                let result = partial.addingReportingOverflow(image.data.count)
                partial = result.overflow ? Int.max : result.partialValue
            }
        )
        guard case let .success(image) = admission else {
            if case let .failure(rejection) = admission { imageAdmissionRejection = rejection }
            return
        }
        imageAdmissionRejection = nil
        pendingImages.append(PendingImage(
            id: UUID(),
            name: url.lastPathComponent,
            mediaType: image.mediaType,
            data: image.data
        ))
    }

    func removePendingImage(_ id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    /// RC8 file mentions are owner-resolved vocabulary, never arbitrary Markdown
    /// destinations. This method is intentionally inert until the caller passes
    /// an already-recognized path token from that Host-backed vocabulary.
    func openKnownProjectPath(_ path: String) {
        guard let hostPathAPI,
              let sessionID = activeSessionID,
              Self.isProjectPathToken(path)
        else { return }
        let resolved = NativeProjectPathResolver.resolve(cwd: activeSessionCWD, path: path)
        Task { [weak self] in
            do {
                let response = try await hostPathAPI.openPath(resolved)
                guard response.opened, self?.activeSessionID == sessionID else { return }
            } catch {
                // RC8 chat rows intentionally keep Host desktop-open failure
                // silent; no local path or transport-private error leaks into
                // untrusted assistant Markdown.
            }
        }
    }

    private static func isProjectPathToken(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == path else { return false }
        return URLComponents(string: trimmed)?.scheme == nil
    }

    /// Source: `sessions.schema.ts:sessionPromptRequestSchema`. The native
    /// composer sends text through the Host and clears only after acceptance.
    func submitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let content: [SessionPromptContent] =
            (text.isEmpty ? [] : [.text(text: text)])
            + pendingImages.map { .image(mediaType: $0.mediaType, data: $0.data.base64EncodedString(), name: $0.name) }
                guard !content.isEmpty,
              !isSubmittingPrompt,
              isPromptRouteAvailable,
              let sessionID = activeSessionID
        else { return }
        if let route = subagentRoute {
            guard route.mode == .continuable,
                  route.parentAvailable,
                  let subagentContinuationAPI
            else { return }
            isSubmittingPrompt = true
            promptTask?.cancel()
            promptTask = Task { [weak self] in
                defer { self?.isSubmittingPrompt = false }
                do {
                    _ = try await subagentContinuationAPI.prompt(.init(
                        parentSessionId: route.parentSessionID,
                        childSessionId: route.childSessionID,
                        content: content,
                        clientTimeZone: TimeZone.current.identifier
                    ))
                    guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                    self?.draft = ""
                    self?.pendingImages = []
                } catch {
                    self?.promptSubmitError = error.localizedDescription
                    // A rejected Host subagent route retains the draft for the
                    // same official retry posture as a session prompt.
                }
            }
            return
        }
        guard sessionCommandService != nil || api != nil else { return }
        isSubmittingPrompt = true
        promptTask?.cancel()
        let commandService = sessionCommandService
        let legacyAPI = api
        promptTask = Task { [weak self] in
            defer { self?.isSubmittingPrompt = false }
            do {
                if let commandService {
                    _ = try await commandService.prompt(
                        sessionID: sessionID,
                        mode: .queue,
                        content: content.map(\.remotePromptContentPart),
                        clientTimeZone: TimeZone.current.identifier
                    )
                } else if let legacyAPI {
                    let response = try await legacyAPI.prompt(sessionID: sessionID, content: content, mode: .queue)
                    guard response.accepted else { return }
                }
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.draft = ""
                self?.pendingImages = []
            } catch {
                self?.promptSubmitError = error.localizedDescription
                // The draft remains available after a rejected prompt, matching
                // the official composer retry posture. Prompt-error presentation
                // is added with the attachment/notice surface.
            }
        }

    }

    // MARK: - Permission selection face

    /// Source: RC8 `permission-presets` command surface. The session-level
    /// `permissions` whole projection advertises choices; `/permission` is the
    /// sole write path. The next projection frame remains the only confirmation.
    func selectPermissionPreset(_ preset: String) {
        guard !isSubmittingPermission,
              preset != "custom",
              sessionCommandService != nil || api != nil,
              let sessionID = activeSessionID,
              let permissions = extensionState?.permissions,
              permissions.currentValue != preset,
              permissions.contains(preset)
        else { return }

        permissionSelectionTask?.cancel()
        permissionSelectionGeneration &+= 1
        let mutationGeneration = permissionSelectionGeneration
        let currentRecoveryGeneration = recoveryGeneration
        let commandService = sessionCommandService
        let legacyAPI = api
        isSubmittingPermission = true
        permissionSelectionTask = Task { [weak self] in
            defer {
                if !Task.isCancelled,
                   self?.activeSessionID == sessionID,
                   self?.recoveryGeneration == currentRecoveryGeneration,
                   self?.permissionSelectionGeneration == mutationGeneration {
                    self?.isSubmittingPermission = false
                }
            }
            do {
                if let commandService {
                    _ = try await commandService.prompt(
                        sessionID: sessionID,
                        mode: .queue,
                        content: [.text("/permission \(preset)")],
                        clientTimeZone: TimeZone.current.identifier
                    )
                } else if let legacyAPI {
                    let response = try await legacyAPI.prompt(
                        sessionID: sessionID,
                        content: [.text(text: "/permission \(preset)")],
                        mode: .queue
                    )
                    guard response.accepted else { return }
                }
                guard !Task.isCancelled,
                      self?.activeSessionID == sessionID,
                      self?.recoveryGeneration == currentRecoveryGeneration,
                      self?.permissionSelectionGeneration == mutationGeneration
                else { return }
                // Deliberately wait for the Host's durable projection push.
            } catch {
                // RC8 leaves the last complete permission projection visible
                // when a command is rejected; no locally synthesized failure.
            }
        }
    }

    // MARK: - Model selection face

    /// Source: RC8 `SessionDirectory.select`. The UI may submit only a complete
    /// currently advertised route; successful presentation follows the exact
    /// Host-confirmed `selected` value and does not edit provider catalog facts.
    func selectModel(provider: String, model: String, reasoningEffort: String?) {
        guard !isSelectingModel,
              sessionCommandService != nil || api != nil,
              let sessionID = activeSessionID,
              let directory = modelDirectory,
              directory.routable,
              directory.contains(provider: provider, model: model, reasoningEffort: reasoningEffort)
        else { return }

        let commandService = sessionCommandService
        let legacyAPI = api
        modelSelectionTask?.cancel()
        modelDirectoryGeneration &+= 1
        modelSelectionGeneration &+= 1
        let directoryGeneration = modelDirectoryGeneration
        let mutationGeneration = modelSelectionGeneration
        let currentRecoveryGeneration = recoveryGeneration
        isSelectingModel = true
        modelDirectoryStatus = .selecting
        modelSelectionTask = Task { [weak self] in
            defer {
                if !Task.isCancelled,
                   self?.activeSessionID == sessionID,
                   self?.recoveryGeneration == currentRecoveryGeneration,
                   self?.modelSelectionGeneration == mutationGeneration {
                    self?.isSelectingModel = false
                }
            }
            do {
                let remoteSelection = RemoteModelSelection(
                    provider: provider,
                    model: model,
                    reasoningEffort: reasoningEffort
                )
                if let commandService {
                    _ = try await commandService.selectModel(
                        sessionID: sessionID,
                        selection: remoteSelection
                    )
                    guard !Task.isCancelled,
                          self?.activeSessionID == sessionID,
                          self?.recoveryGeneration == currentRecoveryGeneration,
                          self?.modelDirectoryGeneration == directoryGeneration,
                          self?.modelSelectionGeneration == mutationGeneration
                    else { return }
                    // rc.1 publishes the effective selection through the
                    // durable `model/selection` projection. Keep the prior
                    // projection visible until that authoritative row arrives.
                } else {
                    guard let legacyAPI else { return }
                    let response = try await legacyAPI.selectModel(.init(
                        sessionId: sessionID,
                        provider: provider,
                        model: model,
                        reasoningEffort: reasoningEffort
                    ))
                    guard !Task.isCancelled,
                          self?.activeSessionID == sessionID,
                          self?.recoveryGeneration == currentRecoveryGeneration,
                          self?.modelDirectoryGeneration == directoryGeneration,
                          self?.modelSelectionGeneration == mutationGeneration
                    else { return }
                    self?.modelDirectory = self?.modelDirectory?.applying(response.selected)
                }
                self?.modelDirectoryStatus = .ready
            } catch {
                guard !Task.isCancelled,
                      self?.activeSessionID == sessionID,
                      self?.recoveryGeneration == currentRecoveryGeneration,
                      self?.modelDirectoryGeneration == directoryGeneration,
                      self?.modelSelectionGeneration == mutationGeneration
                else { return }
                // RC8 keeps the last Host directory selection visible on a
                // rejected mutation; this diagnostic is presentation-only.
                self?.modelDirectoryStatus = .error(error.localizedDescription)
            }
        }
    }

    /// Source: RC8 `SessionDirectory.load`. Retry reloads only the complete
    /// Host `session.models` directory; it never replays or edits conversation
    /// history and is fenced against selection/recovery responses.
    func reloadModelDirectory() {
        guard sessionController != nil || api != nil, let sessionID = activeSessionID else { return }
        let controller = sessionController
        let legacyAPI = api
        modelSelectionTask?.cancel()
        modelSelectionGeneration &+= 1
        isSelectingModel = false
        modelDirectoryGeneration &+= 1
        let directoryGeneration = modelDirectoryGeneration
        let currentRecoveryGeneration = recoveryGeneration
        modelDirectoryStatus = .loading
        modelSelectionTask = Task { [weak self] in
            do {
                if let controller {
                    let catalog = try await controller.modelCatalog()
                    guard !Task.isCancelled,
                          self?.activeSessionID == sessionID,
                          self?.recoveryGeneration == currentRecoveryGeneration,
                          self?.modelDirectoryGeneration == directoryGeneration
                    else { return }
                    self?.remoteModelCatalog = catalog
                    self?.refreshRemoteModelDirectory(sessionID: sessionID)
                } else {
                    guard let legacyAPI else { return }
                    let response = try await legacyAPI.models(sessionID: sessionID)
                    guard !Task.isCancelled,
                          self?.activeSessionID == sessionID,
                          self?.recoveryGeneration == currentRecoveryGeneration,
                          self?.modelDirectoryGeneration == directoryGeneration
                    else { return }
                    self?.modelDirectory = .init(response: response)
                }
                self?.modelDirectoryStatus = .ready
            } catch {
                guard !Task.isCancelled,
                      self?.activeSessionID == sessionID,
                      self?.recoveryGeneration == currentRecoveryGeneration,
                      self?.modelDirectoryGeneration == directoryGeneration
                else { return }
                self?.modelDirectoryStatus = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Queue action face

    /// Source: RC8 `conversation.updateQueue`. Queue items are addressed by the
    /// Host message id and remain visible until the next `session/queue` whole
    /// snapshot retires or replaces them.
    func updateQueuedMessage(itemID: String, action: SessionQueueAction) {
        guard updatingQueueItemID == nil,
              sessionCommandService != nil || api != nil,
              let sessionID = activeSessionID,
              queuedMessages.contains(where: { $0.id == itemID && $0.placement == .queued })
        else { return }
        updatingQueueItemID = itemID
        queueActionFailure = nil
        queueActionCompletion = nil
        queueUpdateTask?.cancel()
        let commandService = sessionCommandService
        let legacyAPI = api
        queueUpdateTask = Task { [weak self] in
            defer {
                if !Task.isCancelled,
                   self?.activeSessionID == sessionID,
                   self?.updatingQueueItemID == itemID {
                    self?.updatingQueueItemID = nil
                }
            }
            do {
                if let commandService {
                    try await commandService.updateQueue(
                        sessionID: sessionID,
                        itemID: itemID,
                        action: action.remoteQueueAction
                    )
                } else if let legacyAPI {
                    let response = try await legacyAPI.updateQueue(
                        .init(sessionId: sessionID, itemId: itemID, action: action)
                    )
                    guard response.accepted else { return }
                }
                guard !Task.isCancelled,
                      self?.activeSessionID == sessionID,
                      self?.queuedMessages.contains(where: { $0.id == itemID && $0.placement == .queued }) == true
                else { return }
                self?.queueActionCompletion = .init(itemID: itemID, action: action)
            } catch {
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.queueActionFailure = .init(itemID: itemID, kind: action.failureKind)
            }
        }
    }

    // MARK: - Goal action face

    /// Source: RC8 `GoalBar.onEdit`. The Host compares the active projection ref;
    /// this method never writes the returned ref into `goal` state.
    func editGoal(objective: String) {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submitGoalAction { api, sessionID, goal in
            _ = try await api.edit(.init(
                sessionId: sessionID,
                ref: .init(id: goal.id, revision: goal.revision),
                objective: trimmed,
                maxGoalRounds: nil
            ))
        }
    }

    /// Source: RC8 `GoalBar.onPause`.
    func pauseGoal() {
        submitGoalAction { api, sessionID, goal in
            _ = try await api.pause(.init(sessionId: sessionID, ref: .init(id: goal.id, revision: goal.revision)))
        }
    }

    /// Source: RC8 `GoalBar.onResume`.
    func resumeGoal() {
        submitGoalAction { api, sessionID, goal in
            _ = try await api.resume(.init(sessionId: sessionID, ref: .init(id: goal.id, revision: goal.revision)))
        }
    }

    /// Source: RC8 `GoalBar.onClear`. Success records only the same-goal
    /// presentation marker until the Host tombstone projection catches up.
    func clearGoal() {
        submitGoalAction(hideGoalOnSuccess: true) { api, sessionID, goal in
            _ = try await api.clear(.init(sessionId: sessionID, ref: .init(id: goal.id, revision: goal.revision)))
        }
    }

    private func submitGoalAction(
        hideGoalOnSuccess: Bool = false,
        _ operation: @escaping @MainActor (any NativeGoalAPI, String, CoreGoalProjection) async throws -> Void
    ) {
        guard !isSubmittingGoal,
              let goalAPI,
              let sessionID = activeSessionID,
              let goal = extensionState?.goal
        else { return }
        isSubmittingGoal = true
        goalActionFailure = nil
        goalTask?.cancel()
        goalTask = Task { [weak self] in
            defer {
                if !Task.isCancelled, self?.activeSessionID == sessionID {
                    self?.isSubmittingGoal = false
                }
            }
            do {
                try await operation(goalAPI, sessionID, goal)
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                if hideGoalOnSuccess { self?.locallyClearedGoalID = goal.id }
            } catch let error as RPCBusinessError {
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.goalActionFailure = .init(message: error.message, code: error.code)
            } catch {
                // Transport and cancellation remain handled by the existing
                // session recovery surfaces; GoalBar never manufactures copy.
            }
        }
    }

    /// Source: RC8 `session.ts:cancel`; a continuable child is cancelled only
    /// through its durable parent-child subagent address, never `session.cancel`.
    func cancelRunningTurn() {
        guard isRunning, let sessionID = activeSessionID else { return }
        // A queued prompt may still be waiting for its receipt while a Host turn
        // becomes cancellable. Its late acceptance must not clear a draft the
        // user kept after choosing Cancel.
        promptTask?.cancel()
        promptTask = nil
        isSubmittingPrompt = false
        if let route = subagentRoute {
            guard route.mode == .continuable, let subagentContinuationAPI else { return }
            cancelTask?.cancel()
            cancelTask = Task { [weak self] in
                do {
                    _ = try await subagentContinuationAPI.interrupt(.init(
                        parentSessionId: route.parentSessionID,
                        childSessionId: route.childSessionID
                    ))
                } catch {
                    // 取消失败保留运行状态
                    self?.cancelAttemptError = error.localizedDescription
                }
            }
            return
        }
        guard sessionCommandService != nil || api != nil else { return }
        cancelTask?.cancel()
        let commandService = sessionCommandService
        let legacyAPI = api
        cancelTask = Task { [weak self] in
            do {
                if let commandService {
                    try await commandService.cancel(sessionID: sessionID)
                } else if let legacyAPI {
                    _ = try await legacyAPI.cancel(sessionID: sessionID)
                }
            } catch {
                // 取消失败保留运行状态
                self?.cancelAttemptError = error.localizedDescription
            }
        }
    }

    /// Source: `sessions.schema.ts:sessionHistoryRequestSchema`. The Host owns
    /// message-boundary paging and returns the authority for `hasMore`.\
    func loadOlderHistory() {
        guard hasMoreHistory,
              !isLoadingOlderHistory,
              let api,
              let sessionID = activeSessionID,
              let beforeSeq = appliedSequences.min()
        else { return }

        isLoadingOlderHistory = true
        olderHistoryTask?.cancel()
        olderHistoryTask = Task { [weak self] in
            defer { self?.isLoadingOlderHistory = false }
            do {
                if let sessionRuntime = self?.sessionRuntime {
                    if let snapshot = try await sessionRuntime.loadOlder() {
                        guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                        self?.installRemoteJournal(snapshot, sessionID: sessionID)
                    }
                    return
                }
                let response = try await api.history(sessionID: sessionID, beforeSeq: beforeSeq, maxMessages: nil)
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.prependConversationWindow(response.events.map(ConversationEventInput.init(entry:)), hasMore: response.hasMore)
                self?.applyHistory(response.events)
                if let projections = response.projections { self?.projections.seed(sessionID: sessionID, baseline: projections) }
                self?.hasMoreHistory = response.hasMore
            } catch {
                self?.historyLoadError = error.localizedDescription
                // Retain the existing official transcript if a backward page
                // fails; a templated error surface follows transport code mapping.
            }
        }
    }

    /// Source: RC8 `Session.resync`. A resident session discards its old
    /// history window and pending server requests, then reopens against a new
    /// Host authority baseline. Cold instances have no transport to rebuild.
    /// Queue/jobs deliberately remain until the fresh `session/subscribed`
    /// mux boundary supplies their ordered whole snapshots.
    func resyncActiveSession() {
        guard let sessionID = activeSessionID,
              api != nil,
              endpoint != nil
        else { return }

        historyTask?.cancel()
        historyTask = nil
        olderHistoryTask?.cancel()
        olderHistoryTask = nil
        isLoadingOlderHistory = false
        recoveryLiveBuffer = []
        recoveryBufferGeneration = nil
        subscribedLastSequence = nil
        invalidateInteractions()
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        resetConversationWindow()
        items = []
        toolInvocations = []
        selectedToolCallID = nil
        appliedSequences = []
        hasMoreHistory = false
        lastError = nil
        phase = .loading(sessionID: sessionID)
        requestAuthorityRecovery(sessionID: sessionID, reason: .residentResync)
    }

    private func observeMux(sessionID: String, endpoint: URL) {
        streamTask?.cancel()
        let client = SSEClient(baseURL: endpoint)
        streamTask = Task { [weak self] in
            let stream = await client.reconnectingStream(.mux)
            do {
                for try await frame in stream {
                    guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                    self?.applyMuxFrame(frame, sessionID: sessionID)
                }
            } catch is CancellationError {
                return
            } catch {
                // A finite retry policy can surface only after reconnect exhaustion.
                // Existing sequence gates retain the last authoritative transcript
                // until the verified Host lifecycle supplies a fresh endpoint.
            }
        }
    }

    private func resetConversationWindow() {
        conversationReducer = ConversationNodeReducer(
            definitions: ConversationCoreNodeRegistry.initialDefinitions()
        )
        chatNodes = []
        trajectoryNodes = []
    }

    private func replaceConversationWindow(_ entries: [ConversationEventInput], hasMore: Bool) {
        conversationReducer = ConversationNodeReducer(
            definitions: ConversationCoreNodeRegistry.initialDefinitions()
        )
        _ = conversationReducer.replaceWindow(entries, hasMore: hasMore)
        chatNodes = conversationReducer.snapshot(target: "chat")
        trajectoryNodes = conversationReducer.snapshot(target: "trajectory")
    }

    private func prependConversationWindow(_ entries: [ConversationEventInput], hasMore: Bool) {
        _ = conversationReducer.prepend(entries, hasMore: hasMore)
        chatNodes = conversationReducer.snapshot(target: "chat")
        trajectoryNodes = conversationReducer.snapshot(target: "trajectory")
    }

    private func appendConversationEvent(_ input: ConversationEventInput) {
        _ = conversationReducer.append(input)
        chatNodes = conversationReducer.snapshot(target: "chat")
        trajectoryNodes = conversationReducer.snapshot(target: "trajectory")
    }

    private func applyHistory(_ entries: [SessionHistoryEntryDTO]) {
        for entry in entries.sorted(by: { $0.event.seq < $1.event.seq }) {
            apply(event: entry.event, view: entry.view)
        }
    }

    private func installRemoteJournal(_ snapshot: SessionJournalSnapshot, sessionID: String) {
        let inputs = snapshot.records.map(ConversationEventInput.init(remoteRecord:))
        replaceConversationWindow(inputs, hasMore: snapshot.hasMore)
        items = []
        toolInvocations = []
        appliedSequences = []
        for record in snapshot.records {
            let input = ConversationEventInput(remoteRecord: record)
            apply(event: input.event)
        }
        projections.seed(sessionID: sessionID, remoteBaseline: snapshot.projections)
        refreshRemoteModelDirectory(sessionID: sessionID)
        hasMoreHistory = snapshot.hasMore
    }

    private func refreshRemoteModelDirectory(sessionID: String) {
        guard let catalog = remoteModelCatalog else { return }
        let current = projections.remoteModelSelection(sessionID: sessionID) ?? catalog.default
        modelDirectory = .init(catalog: catalog, current: current)
    }

    /// Source: `events.ts:MuxFrame` uses frame.method as the event discriminant
    /// in the native SSE transport's server-request envelope.
    /// Core-internal Host mux reducer. The transport owns envelope decoding;
    /// Feature/UI receives the resulting published typed state only.
    func applyMuxFrame(_ frame: RPCServerRequest, sessionID: String) {
        guard activeSessionID == sessionID,
              let object = frame.payload.objectValue,
              object["sessionId"]?.stringValue == sessionID
        else { return }

        switch frame.method {
        case "session/event":
            guard let eventValue = object["event"],
                  let event = decode(SessionEventDTO.self, from: eventValue)
            else { return }
            let view = object["view"].flatMap { decode(ToolEventViewDTO.self, from: $0) }
            if recoveryBufferGeneration != nil {
                bufferRecoveryLiveEvent(event, view: view)
                return
            }
            // Source: RC8 `Session.acceptLiveEvent`: only an open authority
            // window accepts direct events. A failed/cold window must wait for
            // a later history baseline instead of manufacturing a partial log.
            guard case .ready(sessionID: sessionID) = phase else { return }
            guard !liveEventRequiresAuthorityRecovery(event) else {
                bufferRecoveryLiveEvent(event, view: view)
                requestAuthorityRecovery(sessionID: sessionID, reason: .eventGap)
                return
            }
            appendConversationEvent(.init(event: event, view: view))
            apply(event: event, view: view)
        case "session/subscribed":
            applySubscription(object, sessionID: sessionID)
        case "session/projection":
            applyProjection(object, sessionID: sessionID)
        case "session/queue":
            applyQueue(object, sessionID: sessionID)
        case "session/jobs":
            applyJobs(object, sessionID: sessionID)
        case "approval/requested":
            applyApprovalRequest(object, rpcID: frame.rpcId, sessionID: sessionID)
        case "approval/resolved":
            applyApprovalResolution(object)
        case "question/requested":
            applyQuestionRequest(object, rpcID: frame.rpcId, sessionID: sessionID)
        case "question/resolved":
            applyQuestionResolution(object)
        default:
            break
        }
    }

    /// Source: `events.ts:session/projection`; one finished whole value per key,
    /// never a client-side partial fold. The projection store rejects replayed
    /// and lower/equal sequence frames.
    private func applySubscription(_ object: [String: JSONValue], sessionID: String) {
        guard let subscribed = decode(SessionSubscribedDTO.self, from: .object(object)),
              subscribed.sessionId == sessionID
        else { return }
        // A new mux generation may have lost process-local queue/jobs and events
        // past `lastSeq`; wait for its fresh whole-set frames instead of showing
        // phantom work from the prior Host generation.
        let priorWindowHighWatermark = conversationReducer.rawWindow().map(\.event.seq).max()
        subscribedLastSequence = subscribed.lastSeq
        projections.truncate(sessionID: sessionID, after: subscribed.lastSeq)
        queuedMessages = []
        backgroundJobs = []
        // approval/question ServerRequests are generation-bound, exactly like
        // queue/jobs. A restarted Host can no longer resolve an old rpcId; keep
        // no stale takeover visible until the fresh mux baseline re-emits it.
        invalidateInteractions()
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        // RC8 `Session.doOpen` performs a second authority history pull when
        // the mux subscription reports a durable tail beyond the just-installed
        // history window. The inverse rollback case requires the same full
        // recovery so a restarted Host cannot leave a discontinuous window.
        if let priorWindowHighWatermark, subscribed.lastSeq != priorWindowHighWatermark {
            requestAuthorityRecovery(sessionID: sessionID, reason: .subscriptionWatermark)
        }
    }

    private enum AuthorityRecoveryReason {
        case eventGap
        case subscriptionWatermark
        case residentResync
    }

    /// Consumes a durable `session/subscribed` tail only when its installed
    /// authority window is discontinuous. Clearing before the follow-up pull
    /// prevents a stale/underfilled Host page from recursively scheduling the
    /// same recovery forever.
    private func consumeSubscriptionTailMismatch() -> Bool {
        guard let subscribedLastSequence,
              let installedTail = conversationReducer.rawWindow().map(\.event.seq).max(),
              installedTail != subscribedLastSequence
        else { return false }
        self.subscribedLastSequence = nil
        return true
    }

    private func bufferRecoveryLiveEvent(_ event: SessionEventDTO, view: ToolEventViewDTO?) {
        recoveryLiveBuffer.append(.init(event: event, view: view))
    }

    /// RC8 `installWindow` stitches the buffered live tail only after the Host
    /// history cut has replaced the old window. Sequence is the sole dedup key:
    /// replay overlap at or below the recovered tail is ignored, while a newer
    /// frame is applied through the normal typed event path.
    private func stitchRecoveryLiveBuffer(generation: UInt) {
        guard recoveryBufferGeneration == generation else { return }
        let buffered = recoveryLiveBuffer.sorted { $0.event.seq < $1.event.seq }
        recoveryLiveBuffer = []
        recoveryBufferGeneration = nil
        for entry in buffered {
            let tail = conversationReducer.rawWindow().map(\.event.seq).max()
            guard tail == nil || entry.event.seq > tail! else { continue }
            appendConversationEvent(.init(entry: entry))
            apply(event: entry.event, view: entry.view)
        }
    }

    private func liveEventRequiresAuthorityRecovery(_ event: SessionEventDTO) -> Bool {
        let window = conversationReducer.rawWindow()
        guard let highest = window.map(\.event.seq).max() else { return false }
        if window.contains(where: { $0.event.seq == event.seq }) { return false }
        return event.seq != highest + 1
    }

    private func requestAuthorityRecovery(sessionID: String, reason _: AuthorityRecoveryReason) {
        guard let api,
              let endpoint,
              activeSessionID == sessionID
        else { return }
        recoveryTask?.cancel()
        modelSelectionTask?.cancel()
        modelSelectionTask = nil
        modelSelectionGeneration &+= 1
        isSelectingModel = false
        recoveryGeneration &+= 1
        modelDirectoryGeneration &+= 1
        let generation = recoveryGeneration
        recoveryBufferGeneration = generation
        let directoryGeneration = modelDirectoryGeneration
        modelDirectoryStatus = .loading
        recoveryTask = Task { [weak self] in
            do {
                let models = try await api.models(sessionID: sessionID)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.modelDirectoryGeneration == directoryGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                let history = try await api.history(sessionID: sessionID, beforeSeq: nil, maxMessages: nil)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.modelDirectoryGeneration == directoryGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                self?.modelDirectory = .init(response: models)
                self?.modelDirectoryStatus = .ready
                self?.replaceConversationWindow(history.events.map(ConversationEventInput.init(entry:)), hasMore: history.hasMore)
                self?.items = []
                self?.appliedSequences = []
                self?.applyHistory(history.events)
                if let projections = history.projections {
                    self?.projections.seed(sessionID: sessionID, baseline: projections)
                }
                self?.hasMoreHistory = history.hasMore
                self?.phase = .ready(sessionID: sessionID)
                self?.stitchRecoveryLiveBuffer(generation: generation)
                if self?.consumeSubscriptionTailMismatch() == true {
                    self?.requestAuthorityRecovery(sessionID: sessionID, reason: .subscriptionWatermark)
                    return
                }
                self?.resyncSubagentCatalogsAfterRecovery()
                self?.resyncMessageFeedbackAfterRecovery()
            } catch {
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                if case .loading = self?.modelDirectoryStatus {
                    self?.modelDirectoryStatus = .error(error.localizedDescription)
                }
                if self?.recoveryBufferGeneration == generation {
                    self?.recoveryBufferGeneration = nil
                }
                // Keep the last complete authority window visible. A newer
                // mux/recovery generation or a finite stream failure owns any
                // user-facing transport error policy; stale recovery errors do
                // not replace a selected resident transcript.
            }
        }
    }

    private func installRemoteControl(_ snapshot: SessionControlSnapshot) {
        guard let sessionID = activeSessionID else {
            queuedMessages = []
            backgroundJobs = []
            return
        }
        queuedMessages = (snapshot.queues[sessionID] ?? []).map { item in
            let content = item.message.content.map(\.conversationJSONValue)
            let texts = content.map { contentText($0) }
            let allText = texts.allSatisfy(\.isText)
            let flat = texts.map(\.value).joined(separator: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let preview = String(flat.prefix(200)) + (flat.count > 200 ? "…" : "")
            let placement: QueuedMessage.Placement = switch item.placement {
            case .queued: .queued
            case .steering: .steering
            case .context: .context
            }
            return QueuedMessage(
                id: item.id,
                messageID: item.message.id,
                placement: placement,
                role: nil,
                content: content,
                source: nil,
                preview: preview,
                text: allText ? content.compactMap { $0.objectValue?["text"]?.stringValue }.joined() : nil
            )
        }
        backgroundJobs = (snapshot.jobs[sessionID] ?? []).map { job in
            let status: BackgroundJob.Status = switch job.status {
            case .running: .running
            case .stopping: .stopping
            case .completed: .completed
            case .killed: .killed
            case .failed: .failed
            }
            return BackgroundJob(
                id: job.id,
                kind: job.kind,
                label: job.label,
                status: status,
                detail: job.detail,
                startedAt: Int(job.startedAt),
                finishedAt: job.finishedAt.map(Int.init)
            )
        }
        if let baseline = snapshot.projections[sessionID] {
            projections.seed(sessionID: sessionID, remoteBaseline: baseline)
            refreshRemoteModelDirectory(sessionID: sessionID)
        }
    }

    private func applyProjection(_ object: [String: JSONValue], sessionID: String) {
        guard let key = object["key"]?.stringValue,
              let value = object["value"],
              let seq = object["seq"]?.numberValue
        else { return }
        projections.apply(sessionID: sessionID, key: key, value: value, seq: Int(seq))
    }

    private func applyQueue(_ object: [String: JSONValue], sessionID: String) {
        guard let frame = decode(SessionQueueFrameDTO.self, from: .object(object)),
              frame.sessionId == sessionID
        else { return }
        queuedMessages = frame.items.map { item in
            let texts = item.message.content.map { contentText($0) }
            let allText = texts.allSatisfy { $0.isText }
            let flat = texts.map(\.value).joined(separator: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let preview = String(flat.prefix(200)) + (flat.count > 200 ? "…" : "")
            return QueuedMessage(
                id: item.id,
                messageID: item.message.id,
                placement: QueuedMessage.Placement(rawValue: item.placement.rawValue)!,
                role: item.message.role,
                content: item.message.content,
                source: item.message.source,
                preview: preview,
                text: allText ? item.message.content.compactMap { $0.objectValue?["text"]?.stringValue }.joined() : nil
            )
        }
    }

    private func applyJobs(_ object: [String: JSONValue], sessionID: String) {
        guard let frame = decode(SessionJobsFrameDTO.self, from: .object(object)),
              frame.sessionId == sessionID
        else { return }
        // `session/jobs` is a complete authority snapshot: `[]` and an absent
        // baseline both mean no jobs, never a delta to merge.
        backgroundJobs = frame.jobs.map { job in
            BackgroundJob(
                id: job.id,
                kind: job.kind,
                label: job.label,
                status: BackgroundJob.Status(rawValue: job.status.rawValue)!,
                detail: job.detail,
                startedAt: job.startedAt,
                finishedAt: job.finishedAt
            )
        }
    }

    private func contentText(_ value: JSONValue) -> (isText: Bool, value: String) {
        guard let object = value.objectValue,
              let type = object["type"]?.stringValue
        else { return (false, "[unknown]") }
        if type == "text", let text = object["text"]?.stringValue {
            return (true, text)
        }
        return (false, "[\(type)]")
    }

    private func applyApprovalRequest(_ object: [String: JSONValue], rpcID: String, sessionID: String) {
        guard let approvalID = object["approvalId"]?.stringValue,
              let toolName = object["toolName"]?.stringValue
        else { return }
        guard pendingApproval?.rpcID != rpcID else { return }
        invalidateInteractions()
        pendingApproval = PendingApproval(
            rpcID: rpcID,
            sessionID: sessionID,
            approvalID: approvalID,
            toolName: toolName,
            callID: object["callId"]?.stringValue,
            reason: object["reason"]?.stringValue
        )
        isSubmittingApproval = false
    }

    private func applyApprovalResolution(_ object: [String: JSONValue]) {
        guard let approvalID = object["approvalId"]?.stringValue,
              pendingApproval?.approvalID == approvalID
        else { return }
        pendingApproval = nil
        invalidateApprovalSubmission()
    }

    private func applyQuestionRequest(_ object: [String: JSONValue], rpcID: String, sessionID: String) {
        guard let values = object["questions"]?.arrayValue else { return }
        let items = values.compactMap(questionItem)
        guard !items.isEmpty, items.count == values.count else { return }
        guard pendingQuestion?.rpcID != rpcID else { return }
        invalidateInteractions()
        pendingQuestion = PendingQuestion(rpcID: rpcID, sessionID: sessionID, items: items)
        isSubmittingQuestion = false
    }

    private func applyQuestionResolution(_ object: [String: JSONValue]) {
        guard let rpcID = object["questionRpcId"]?.stringValue,
              pendingQuestion?.rpcID == rpcID
        else { return }
        pendingQuestion = nil
        invalidateQuestionSubmission()
    }

    private func questionItem(_ value: JSONValue) -> PendingQuestion.Item? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let question = object["question"]?.stringValue
        else { return nil }
        let options: [PendingQuestion.Option]
        if let values = object["options"]?.arrayValue {
            options = values.compactMap { value in
                guard let option = value.objectValue,
                      let label = option["label"]?.stringValue
                else { return nil }
                return PendingQuestion.Option(label: label, detail: option["description"]?.stringValue)
            }
            guard options.count == values.count else { return nil }
        } else {
            options = []
        }
        let intent: PendingQuestion.Item.Intent?
        if let rawIntent = object["intent"]?.objectValue {
            guard let kind = rawIntent["kind"]?.stringValue else { return nil }
            switch kind {
            case "plan-review":
                guard let approve = rawIntent["approve"]?.stringValue else { return nil }
                intent = .planReview(approve: approve)
            default:
                return nil
            }
        } else {
            intent = nil
        }
        return PendingQuestion.Item(
            id: id,
            question: question,
            header: object["header"]?.stringValue,
            detail: object["detail"]?.stringValue,
            options: options,
            multiSelect: object["multiSelect"]?.boolValue ?? false,
            intent: intent
        )
    }

    private func invalidateApprovalSubmission() {
        approvalSubmissionTask?.cancel()
        approvalSubmissionTask = nil
        isSubmittingApproval = false
    }

    private func invalidateQuestionSubmission() {
        questionSubmissionTask?.cancel()
        questionSubmissionTask = nil
        isSubmittingQuestion = false
    }

    /// Invalidates both takeover write paths when their shared session/mux
    /// authority changes. A new request gets a distinct generation even if the
    /// Host has reused an RPC id after reconnect.
    private func invalidateInteractions() {
        interactionGeneration &+= 1
        invalidateApprovalSubmission()
        invalidateQuestionSubmission()
    }

    /// Source: `PendingApproval.answer`; a panel remains mounted until the Host
    /// broadcasts `approval/resolved`, even after an accepted carrier receipt.
    func answerApproval(allowOnce: Bool) {
        guard let approval = pendingApproval,
              let api,
              let approvalID = approval.approvalID,
              !isSubmittingApproval
        else { return }
        isSubmittingApproval = true
        let outcome: ApprovalOutcome = allowOnce ? .allowedOnce : .rejected
        let generation = interactionGeneration
        approvalSubmissionTask = Task { [weak self] in
            do {
                let receipt = try await api.answerApproval(
                    rpcID: approval.rpcID,
                    sessionID: approval.sessionID,
                    approvalID: approvalID,
                    outcome: outcome
                )
                guard !Task.isCancelled,
                      let self,
                      self.interactionGeneration == generation,
                      let current = self.pendingApproval,
                      current.rpcID == approval.rpcID,
                      current.sessionID == approval.sessionID,
                      current.approvalID == approval.approvalID
                else { return }
                self.approvalSubmissionTask = nil
                if !receipt.accepted { self.isSubmittingApproval = false }
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.interactionGeneration == generation,
                      let current = self.pendingApproval,
                      current.rpcID == approval.rpcID,
                      current.sessionID == approval.sessionID,
                      current.approvalID == approval.approvalID
                else { return }
                self.approvalSubmissionTask = nil
                self.isSubmittingApproval = false
            }
        }
    }

    /// Source: `PendingQuestion.answer`; all items in the non-empty Host batch
    /// are returned together in the approved `QuestionAnswer` value shape.
    func answerQuestion(_ answers: [QuestionAnswer]) {
        guard let question = pendingQuestion,
              let api,
              !isSubmittingQuestion,
              answers.count == question.items.count
        else { return }
        isSubmittingQuestion = true
        let responseAnswers = answers.map { QuestionAnswerResponse(id: $0.id, selected: $0.selected, custom: $0.custom) }
        let generation = interactionGeneration
        questionSubmissionTask = Task { [weak self] in
            do {
                let receipt = try await api.answerQuestion(rpcID: question.rpcID, sessionID: question.sessionID, answers: responseAnswers)
                guard !Task.isCancelled,
                      let self,
                      self.interactionGeneration == generation,
                      let current = self.pendingQuestion,
                      current.rpcID == question.rpcID,
                      current.sessionID == question.sessionID
                else { return }
                self.questionSubmissionTask = nil
                if !receipt.accepted { self.isSubmittingQuestion = false }
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.interactionGeneration == generation,
                      let current = self.pendingQuestion,
                      current.rpcID == question.rpcID,
                      current.sessionID == question.sessionID
                else { return }
                self.questionSubmissionTask = nil
                self.isSubmittingQuestion = false
            }
        }
    }

    /// Source: `PendingQuestion.cancel`; cancellation is a failure result, not
    /// an invented success outcome, and is resolved by the Host broadcast.
    func cancelQuestion() {
        guard let question = pendingQuestion,
              let api,
              !isSubmittingQuestion
        else { return }
        isSubmittingQuestion = true
        let generation = interactionGeneration
        questionSubmissionTask = Task { [weak self] in
            do {
                let receipt = try await api.cancelQuestion(rpcID: question.rpcID)
                guard !Task.isCancelled,
                      let self,
                      self.interactionGeneration == generation,
                      let current = self.pendingQuestion,
                      current.rpcID == question.rpcID,
                      current.sessionID == question.sessionID
                else { return }
                self.questionSubmissionTask = nil
                if !receipt.accepted { self.isSubmittingQuestion = false }
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.interactionGeneration == generation,
                      let current = self.pendingQuestion,
                      current.rpcID == question.rpcID,
                      current.sessionID == question.sessionID
                else { return }
                self.questionSubmissionTask = nil
                self.isSubmittingQuestion = false
            }
        }
    }

    private func apply(event: SessionEventDTO, view: ToolEventViewDTO? = nil) {
        if event.type != "assistant/chunk" {
            guard appliedSequences.insert(event.seq).inserted else { return }
        }

        switch event.type {
        case "user/message":
            // Source: `SessionQueueMirror.acceptDurable`. A transient steering
            // row belongs to the queue snapshot only until its matching durable
            // user message has entered the contiguous Host log.
            if let messageID = event.data.objectValue?["id"]?.stringValue {
                queuedMessages.removeAll { $0.placement == .steering && $0.messageID == messageID }
            }
            guard let text = textContent(in: event.data) else { return }
            upsert(TranscriptItem(
                id: "event-\(event.seq)",
                role: .user,
                text: text,
                isStreaming: false,
                time: event.time,
                sequence: event.seq
            ))
        case "assistant/message":
            guard let text = textContent(in: event.data.objectValue?["message"] ?? event.data) else { return }
            settleStreaming()
            upsert(TranscriptItem(
                id: "event-\(event.seq)",
                role: .assistant,
                text: text,
                isStreaming: false,
                time: event.time,
                sequence: event.seq
            ))
        case "turn/start":
            isRunning = true
        case "assistant/chunk":
            isRunning = true
            applyAssistantChunk(event)
        case "tool/call":
            // The `for` discriminator is part of the official ToolEventView
            // contract. A mismatched or unknown target receives no specialized
            // renderer and safely retains the generic arguments/output path.
            applyToolCall(event, view: view?.for == "call" ? view : nil)
        case "tool/result":
            applyToolResult(event, view: view?.for == "result" ? view : nil)
        case "turn/end":
            isRunning = false
            settleStreaming()
        default:
            break
        }
    }

    /// Source: `assistant/chunk` payloads have `turn`, `step`, and a chunk whose
    /// official text branch is `{ type: "text-delta", index, text }`.
    private func applyAssistantChunk(_ event: SessionEventDTO) {
        guard let data = event.data.objectValue,
              let turn = data["turn"]?.numberValue,
              let step = data["step"]?.numberValue,
              let chunk = data["chunk"]?.objectValue,
              chunk["type"]?.stringValue == "text-delta",
              let index = chunk["index"]?.numberValue,
              let text = chunk["text"]?.stringValue
        else { return }

        let id = "stream-\(Int(turn))-\(Int(step))-\(Int(index))"
        if let existing = items.firstIndex(where: { $0.id == id }) {
            items[existing].text += text
            items[existing].isStreaming = true
        } else {
            upsert(TranscriptItem(
                id: id,
                role: .assistant,
                text: text,
                isStreaming: true,
                time: event.time,
                sequence: event.seq
            ))
        }
    }

    private func applyToolCall(_ event: SessionEventDTO, view: ToolEventViewDTO?) {
        guard let data = event.data.objectValue,
              let callID = data["callId"]?.stringValue,
              let name = data["name"]?.stringValue,
              let arguments = data["arguments"]?.stringValue
        else { return }
        guard !toolInvocations.contains(where: { $0.id == callID }) else { return }
        let invocation = ToolInvocation(
            id: callID,
            name: name,
            arguments: arguments,
            output: nil,
            textOutput: nil,
            errorName: nil,
            errorCode: nil,
            state: .running,
            sequence: event.seq,
            callView: view,
            resultView: nil
        )
        // Sorted-insert by sequence; keeps the timeline merge linear and avoids
        // re-sorting the whole array on every tool call.
        var lower = toolInvocations.startIndex
        var upper = toolInvocations.endIndex
        while lower < upper {
            let mid = (lower + upper) / 2
            if toolInvocations[mid].sequence < invocation.sequence {
                lower = mid + 1
            } else {
                upper = mid
            }
        }
        toolInvocations.insert(invocation, at: lower)
    }

    private func applyToolResult(_ event: SessionEventDTO, view: ToolEventViewDTO?) {
        guard let data = event.data.objectValue,
              let message = data["message"]?.objectValue,
              let source = message["source"]?.objectValue,
              let callID = source["callId"]?.stringValue
        else { return }
        let error = data["error"]?.objectValue
        let errorName = error?["name"]?.stringValue
        let errorCode = error?["code"]?.stringValue
        let output = resultText(in: message, errorName: errorName, errorCode: errorCode)
        let textOutput = textResult(in: message)
        guard let index = toolInvocations.firstIndex(where: { $0.id == callID }) else { return }
        toolInvocations[index].output = output
        toolInvocations[index].textOutput = textOutput
        toolInvocations[index].errorName = errorName
        toolInvocations[index].errorCode = errorCode
        toolInvocations[index].state = errorCode == "interrupted" ? .stopped : (errorCode == nil ? .completed : .failed)
        toolInvocations[index].resultView = view ?? toolInvocations[index].resultView
    }

    func selectToolCall(_ callID: String?) {
        selectedToolCallID = callID
    }

    /// Source: `ApprovalPanel.tsx:commandOf`; the paired call may have malformed
    /// arguments, in which case the official panel simply omits its command row.
    func command(for approval: PendingApproval) -> String? {
        guard let callID = approval.callID,
              let invocation = toolInvocations.first(where: { $0.id == callID }),
              let data = invocation.arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["command"] as? String
    }

    /// Snapshot-only Host-shaped Jobs fixture. It represents the same complete
    /// `session/jobs` snapshot that the Host owns in production: one live bash
    /// task and one settled bash task. It exists only for paired visual capture.
    func loadSnapshotJobsFixture() {
        let sessionID = "fx-alpha"
        let now = Int(Date().timeIntervalSince1970 * 1_000)
        phase = .ready(sessionID: sessionID)
        activeSessionID = sessionID
        let conversationEvents = [
            ConversationEventInput(event: SessionEventDTO(
                type: "user/message",
                seq: 1,
                time: Double(now),
                data: .object([
                    "id": .string("snapshot-jobs-user"),
                    "content": .array([.object(["type": .string("text"), "text": .string("Reply with the single word LIGHTHOUSE and stop.")])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: .string("append")
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "turn/start",
                seq: 2,
                time: Double(now),
                data: .object(["turn": .number(1)])
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "step/start",
                seq: 3,
                time: Double(now),
                data: .object(["turn": .number(1), "step": .number(1)])
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "assistant/message",
                seq: 4,
                time: Double(now),
                data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "message": .object([
                        "id": .string("snapshot-jobs-assistant"),
                        "content": .array([.object(["type": .string("text"), "text": .string("LIGHTHOUSE")])]),
                    ]),
                ]),
                surfaceOp: .string("append")
            )),
        ]
        replaceConversationWindow(conversationEvents, hasMore: false)
        items = []
        for input in conversationEvents {
            apply(event: input.event)
        }
        toolInvocations = []
        queuedMessages = []
        backgroundJobs = [
            BackgroundJob(
                id: "bash-1",
                kind: "bash",
                label: "sleep 60",
                status: .running,
                detail: nil,
                startedAt: now,
                finishedAt: nil
            ),
            BackgroundJob(
                id: "bash-2",
                kind: "bash",
                label: "pnpm run build",
                status: .completed,
                detail: nil,
                startedAt: now,
                finishedAt: now
            )
        ]
        pendingApproval = nil
        pendingQuestion = nil
        modelDirectory = nil
        modelDirectoryStatus = .idle
        selectedToolCallID = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        isRunning = false
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        appliedSequences = Set(conversationEvents.map(\.event.seq))
    }

    /// Snapshot-only Host-shaped `session.models` fixture matching the locked
    /// Web capture's real default route. It never stands in for a live selection
    /// mutation or synthesizes provider capabilities absent from that capture.
    func loadSnapshotModelSelectionFixture() {
        let sessionID = "fx-alpha"
        phase = .ready(sessionID: sessionID)
        activeSessionID = sessionID
        items = []
        resetConversationWindow()
        toolInvocations = []
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = .init(response: .init(
            current: .init(provider: "deepseek-official", model: "deepseek-v4-flash", reasoningEffort: nil),
            routable: true,
            groups: [
                .init(id: "deepseek-official", name: "DeepSeek", models: [
                    .init(id: "deepseek-v4-flash", name: "DeepSeek-V4-Flash", description: nil, reasoning: nil),
                ]),
            ],
            failures: []
        ))
        modelDirectoryStatus = .ready
        isSelectingModel = false
        selectedToolCallID = nil
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        isRunning = false
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        appliedSequences = []
    }

    /// Snapshot-only Host-shaped `permissions` fixture. It represents the
    /// complete projection produced by the optional RC8 permission service; the
    /// current session command path is intentionally not invoked here.
    func loadSnapshotPermissionFixture() {
        let sessionID = "fx-alpha"
        phase = .ready(sessionID: sessionID)
        activeSessionID = sessionID
        items = []
        resetConversationWindow()
        toolInvocations = []
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
        modelDirectoryStatus = .idle
        projections.remove(sessionID: sessionID)
        projections.apply(
            sessionID: sessionID,
            key: "permissions",
            value: .object([
                "options": .array([
                    .object([
                        "value": .string("workspace-write"),
                        "name": .string("workspace-write"),
                        "description": .string("Write inside the workspace and permitted temporary directories; wider retries require approval."),
                    ]),
                    .object([
                        "value": .string("danger-full-access"),
                        "name": .string("danger-full-access"),
                        "description": .string("Full file access without approval prompts."),
                    ]),
                ]),
                "currentValue": .string("workspace-write"),
            ]),
            seq: 1
        )
        isSelectingModel = false
        isSubmittingPermission = false
        selectedToolCallID = nil
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        isRunning = false
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        appliedSequences = []
    }

    /// Snapshot-only Host-shaped approval fixture. It exercises the same
    /// `PendingApproval` holder that a live `approval/requested` mux frame sets.
    func loadSnapshotApprovalFixture() {
        let sessionID = "fx-alpha"
        phase = .ready(sessionID: sessionID)
        activeSessionID = sessionID
        items = []
        resetConversationWindow()
        toolInvocations = []
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
        modelDirectoryStatus = .idle
        pendingApproval = PendingApproval(
            rpcID: "fx-rpc-approval",
            sessionID: sessionID,
            approvalID: "fx-approval-1",
            toolName: "dangerous_tool",
            callID: nil,
            reason: "fixture 常驻审批（可答：批准/拒绝后消失）"
        )
        pendingQuestion = nil
        selectedToolCallID = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        isRunning = true
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        appliedSequences = []
    }

    /// Snapshot-only Host-shaped question fixture. It exercises a single-choice
    /// question with a header, an option description, and the final Submit path.
    func loadSnapshotQuestionFixture() {
        let sessionID = "fx-alpha"
        phase = .ready(sessionID: sessionID)
        activeSessionID = sessionID
        items = []
        resetConversationWindow()
        toolInvocations = []
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
        modelDirectoryStatus = .idle
        pendingApproval = nil
        pendingQuestion = PendingQuestion(
            rpcID: "fx-rpc-question",
            sessionID: sessionID,
            items: [
                PendingQuestion.Item(
                    id: "harness-profile",
                    question: "你现在更想招哪类 Agent/Harness 候选人？",
                    header: "偏好",
                    detail: nil,
                    options: [
                        PendingQuestion.Option(label: "工程落地型 (Recommended)", detail: "更看重能直接做 runtime、tool executor、sandbox、trace 和线上问题排查。"),
                        PendingQuestion.Option(label: "研究潜力型", detail: "更看重 Agent 理解、训练评测思路和长期成长空间。"),
                        PendingQuestion.Option(label: "均衡型", detail: "同时要求工程能力和 Agent 认知，但可能筛选门槛更高。")
                    ],
                    multiSelect: false,
                    intent: nil
                ),
                PendingQuestion.Item(
                    id: "work-mode",
                    question: "你希望候选人优先展示哪种工作方式？",
                    header: "方式",
                    detail: nil,
                    options: [
                        PendingQuestion.Option(label: "先做小型原型 (Recommended)", detail: "用可运行结果尽快验证关键假设。"),
                        PendingQuestion.Option(label: "先写完整设计", detail: "先收敛边界、协议和风险，再开始实现。")
                    ],
                    multiSelect: false,
                    intent: nil
                ),
                PendingQuestion.Item(
                    id: "signals",
                    question: "哪些面试信号最重要？",
                    header: "信号",
                    detail: "按当前招聘目标选择；跳过则视为不设偏好。",
                    options: [
                        PendingQuestion.Option(label: "系统设计", detail: nil),
                        PendingQuestion.Option(label: "代码质量", detail: nil),
                        PendingQuestion.Option(label: "Agent 产品判断", detail: nil)
                    ],
                    multiSelect: true,
                    intent: nil
                )
            ]
        )
        selectedToolCallID = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        isRunning = true
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        appliedSequences = []
    }

    /// Snapshot-only Host-shaped fixture. It drives the same native transcript
    /// and tool detail views as live SSE reducer output, without becoming a
    /// production fallback for disconnected sessions.
    func loadSnapshotToolingFixture() {
        let sessionID = "snapshot-tooling"
        phase = .ready(sessionID: sessionID)
        activeSessionID = sessionID
        let conversationEvents = [
            ConversationEventInput(event: SessionEventDTO(
                type: "user/message",
                seq: 101,
                time: 101,
                data: .object([
                    "id": .string("event-101"),
                    "content": .array([.object(["type": .string("text"), "text": .string("Read the project instructions.")])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: .string("append")
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "turn/start",
                seq: 102,
                time: 102,
                data: .object(["turn": .number(1)])
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "step/start",
                seq: 103,
                time: 103,
                data: .object(["turn": .number(1), "step": .number(1)])
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "assistant/message",
                seq: 104,
                time: 104,
                data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "message": .object([
                        "id": .string("event-104"),
                        "content": .array([.object(["type": .string("text"), "text": .string("I found the requested instructions.")])]),
                    ]),
                ]),
                surfaceOp: .string("append")
            )),
        ]
        replaceConversationWindow(conversationEvents, hasMore: false)
        items = []
        for input in conversationEvents {
            apply(event: input.event)
        }
        toolInvocations = [
            ToolInvocation(
                id: "snapshot-read",
                name: "read",
                arguments: "{\"path\":\"README.md\"}",
                output: "# Project instructions",
                textOutput: "# Project instructions",
                errorName: nil,
                errorCode: nil,
                state: .completed,
                sequence: 102,
                callView: nil,
                resultView: nil
            ),
            ToolInvocation(
                id: "snapshot-bash",
                name: "bash",
                arguments: "pwd",
                output: nil,
                textOutput: nil,
                errorName: nil,
                errorCode: nil,
                state: .running,
                sequence: 103,
                callView: nil,
                resultView: nil
            )
        ]
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
        modelDirectoryStatus = .idle
        pendingApproval = nil
        pendingQuestion = nil
        selectedToolCallID = "snapshot-read"
        isRunning = true
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        appliedSequences = Set(conversationEvents.map(\.event.seq))
    }

    /// Snapshot-only RC8 `ui-deliverables` fixture. The reducer derives the
    /// completed turn's locations from a real diff card and successful result;
    /// the assistant's closing sequence selects the correct turn tail.
    func loadSnapshotDeliverablesFixture() {
        let sessionID = "snapshot-deliverables"
        phase = .ready(sessionID: sessionID)
        activeSessionID = sessionID
        let producedPaths = [
            "关于我.md", "index.html", "long-generated-experience-specification-for-produced-files-overflow.md",
            "styles.css", "app.ts", "schema.json", "README.md", "preview.svg", "notes.txt", "manifest.yaml",
        ]
        // Match RC8 `produced-files.e2e.ts`: each successful write owns one
        // location and produces a visible typed tool row before the turn tail.
        let writeEvents = producedPaths.enumerated().flatMap { index, path -> [ConversationEventInput] in
            let callID = "write-\(index + 1)"
            let callSequence = 303 + index * 2
            let arguments = "{\"file_path\":\"\(path)\",\"content\":\"content of \(path)\"}"
            return [
                ConversationEventInput(
                    event: SessionEventDTO(
                        type: "tool/call",
                        seq: callSequence,
                        time: Double(callSequence),
                        data: .object([
                            "turn": .number(1),
                            "callId": .string(callID),
                            "name": .string("write"),
                            "arguments": .string(arguments),
                        ]),
                        surfaceOp: .string("append")
                    ),
                    view: ToolEventViewDTO(for: "call", view: .object([
                        "card": .string("diff"),
                        "locations": .array([.object(["path": .string(path)])]),
                    ]))
                ),
                ConversationEventInput(event: SessionEventDTO(
                    type: "tool/result",
                    seq: callSequence + 1,
                    time: Double(callSequence + 1),
                    data: .object([
                        "turn": .number(1),
                        "message": .object([
                            "source": .object(["callId": .string(callID)]),
                            "content": .array([.object([:])]),
                        ]),
                    ]),
                    surfaceOp: .string("append")
                )),
            ]
        }
        let conversationEvents = [
            ConversationEventInput(event: SessionEventDTO(
                type: "user/message",
                seq: 301,
                time: 301,
                data: .object([
                    "id": .string("deliverables-user"),
                    "content": .array([.object(["type": .string("text"), "text": .string("Create the site files.")])]),
                    "source": .object(["kind": .string("user")]),
                ]),
                surfaceOp: .string("append")
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "turn/start",
                seq: 302,
                time: 302,
                data: .object(["turn": .number(1)])
            )),
        ] + writeEvents + [
            // The reducer materializes an assistant-step node only from a
            // `step/start` anchor (same as every other fixture and the locked
            // official event shape, where tool executions run between steps),
            // so the closing assistant message below must open its own step.
            ConversationEventInput(event: SessionEventDTO(
                type: "step/start",
                seq: 323,
                time: 323,
                data: .object(["turn": .number(1), "step": .number(1)])
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "assistant/message",
                seq: 324,
                time: 324,
                data: .object([
                    "turn": .number(1),
                    "step": .number(1),
                    "message": .object([
                        "id": .string("deliverables-assistant"),
                        "content": .array([.object(["type": .string("text"), "text": .string("Created the site.\n\nPRODUCED_FILES_DONE")])]),
                    ]),
                ]),
                surfaceOp: .string("append")
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "turn/end",
                seq: 325,
                time: 325,
                data: .object(["turn": .number(1)])
            )),
        ]
        replaceConversationWindow(conversationEvents, hasMore: false)
        items = []
        for input in conversationEvents {
            apply(event: input.event)
        }
        // Mirror the ten successful `write` tool rows the transcript above
        // replays, so the inspector and the produced-files turn tail agree.
        toolInvocations = producedPaths.enumerated().map { index, path in
            ToolInvocation(
                id: "write-\(index + 1)",
                name: "write",
                arguments: "{\"file_path\":\"\(path)\",\"content\":\"content of \(path)\"}",
                output: nil,
                textOutput: nil,
                errorName: nil,
                errorCode: nil,
                state: .completed,
                sequence: 303 + index * 2,
                callView: nil,
                resultView: nil
            )
        }
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
        modelDirectoryStatus = .idle
        pendingApproval = nil
        pendingQuestion = nil
        selectedToolCallID = nil
        isRunning = false
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        appliedSequences = Set(conversationEvents.map(\.event.seq))
    }

    /// Snapshot-only message-feedback fixture. It settles the tooling assistant
    /// through the same reducer event path and supplies a complete Host-shaped
    /// sidecar solely for paired native visual capture.
    func loadSnapshotFeedbackFixture() {
        loadSnapshotToolingFixture()
        let settled = ConversationEventInput(event: SessionEventDTO(
            type: "turn/end",
            seq: 105,
            time: 105,
            data: .object(["turn": .number(1)])
        ))
        let window = conversationReducer.rawWindow() + [settled]
        replaceConversationWindow(window, hasMore: false)
        apply(event: settled.event)
        messageFeedbackItems = [
            "event-104": .init(
                messageId: "event-104",
                rating: .positive,
                note: "Useful implementation summary.",
                version: "snapshot-feedback-v1",
                createdAt: 104,
                updatedAt: 105
            ),
        ]
        isMessageFeedbackAvailable = true
        isLoadingMessageFeedback = false
        failedMessageFeedbackLoad = false
        isSubmittingMessageFeedback = false
        messageFeedbackActionFailureCode = nil
        messageFeedbackMutationMessageID = nil
    }

    /// Snapshot-only model-retry fixture. It appends the RC8-shaped scheduled
    /// attempt through the reducer, rather than injecting a Core retry node.
    func loadSnapshotRetryFixture() {
        loadSnapshotToolingFixture()
        let retry = ConversationEventInput(event: SessionEventDTO(
            type: "llm/retry",
            seq: 105,
            time: 105,
            data: .object([
                "retryId": .string("snapshot-retry"),
                "retry": .number(1),
                "turn": .number(1),
                "step": .number(1),
                "mode": .string("normal"),
                "maxRetries": .number(3),
                "delayMs": .number(1_250),
                "failure": .object([
                    "message": .string("provider busy"),
                    "code": .string("rate_limit"),
                ]),
            ])
        ))
        appendConversationEvent(retry)
        apply(event: retry.event)
        isRunning = true
        appliedSequences.insert(retry.event.seq)
    }

    /// Snapshot-only landed compaction fixture. It appends the same typed
    /// checkpoint/summary shape that the Core reducer regression certifies.
    func loadSnapshotCompactionFixture() {
        loadSnapshotToolingFixture()
        let events = [
            ConversationEventInput(event: SessionEventDTO(
                type: "compaction/start", seq: 104, time: 104,
                data: .object(["compactionId": .string("snapshot-compact")])
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "compaction/summary", seq: 105, time: 105,
                data: .object([
                    "compactionId": .string("snapshot-compact"),
                    "summary": .string("The earlier workspace review and source inspection were condensed into this checkpoint."),
                    "shadowedItemCount": .number(3),
                    "shadowedTokenCount": .number(99),
                ])
            )),
            ConversationEventInput(event: SessionEventDTO(
                type: "user/message", seq: 106, time: 106,
                data: .object([
                    "id": .string("snapshot-compact-checkpoint"),
                    "source": .object([
                        "kind": .string("plugin"),
                        "plugin": .string("compact"),
                        "compactionId": .string("snapshot-compact"),
                    ]),
                    "content": .array([]),
                ]),
                surfaceOp: .object([
                    "op": .string("replace"),
                    "start": .number(1),
                    "end": .number(9),
                ])
            )),
        ]
        for input in events {
            appendConversationEvent(input)
            apply(event: input.event)
        }
        isRunning = false
        appliedSequences.formUnion(events.map { $0.event.seq })
    }

    /// Snapshot-only queue-dock fixture. It contains only `placement=queued`
    /// Host rows, including a non-text item that verifies the official disabled
    /// edit affordance. It never creates an action API or local queue mutation.
    func loadSnapshotQueueFixture() {
        loadSnapshotToolingFixture()
        queuedMessages = [
            QueuedMessage(
                id: "snapshot-queue-text",
                messageID: "snapshot-queue-message-text",
                placement: .queued,
                role: "user",
                content: [.object(["type": .string("text"), "text": .string("Update the native screenshot baseline")])],
                source: .object(["kind": .string("user")]),
                preview: "Update the native screenshot baseline",
                text: "Update the native screenshot baseline"
            ),
            QueuedMessage(
                id: "snapshot-queue-image",
                messageID: "snapshot-queue-message-image",
                placement: .queued,
                role: "user",
                content: [.object(["type": .string("image"), "data": .string("fixture")])],
                source: .object(["kind": .string("user")]),
                preview: "[image]",
                text: nil
            ),
        ]
        isRunning = true
        selectedToolCallID = nil
    }

    /// Snapshot-only todo-dock fixture. It injects the same whole-list Host
    /// projection consumed in production, never a local checklist substitute.
    func loadSnapshotTodoFixture() {
        loadSnapshotToolingFixture()
        guard let sessionID = activeSessionID else { preconditionFailure("todo fixture requires an active snapshot session") }
        projections.apply(sessionID: sessionID, key: "todos", value: .array([
            .object(["content": .string("Inspect the project instructions"), "status": .string("completed")]),
            .object(["content": .string("Implement the native todo dock"), "status": .string("in_progress")]),
            .object(["content": .string("Run the paired visual review"), "status": .string("pending")]),
        ]), seq: 105)
        selectedToolCallID = nil
        isRunning = false
    }

    /// Snapshot-only goal-dock fixture. It mirrors the live whole `goal`
    /// projection consumed by the native strip; mutation actions remain absent
    /// because a snapshot must never issue a Host RPC.
    func loadSnapshotGoalFixture() {
        loadSnapshotToolingFixture()
        guard let sessionID = activeSessionID else { preconditionFailure("goal fixture requires an active snapshot session") }
        projections.apply(sessionID: sessionID, key: "goal", value: .object([
            "goal": .object([
                "id": .string("snapshot-goal"),
                "revision": .number(1),
                "objective": .string("Rebuild the official client as a native macOS app"),
                "phase": .string("active"),
                "maxGoalRounds": .number(4),
            ]),
            "roundsStarted": .number(1),
            "createdAt": .number(100),
            "updatedAt": .number(100),
        ]), seq: 105)
        selectedToolCallID = nil
        isRunning = false
    }

    private func settleStreaming() {
        for index in items.indices where items[index].isStreaming {
            items[index].isStreaming = false
        }
    }

    private func upsert(_ item: TranscriptItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            // Items keep the (sequence, id) ascending invariant; a sorted insert
            // replaces the full-array re-sort that made a long stream O(n log n).
            var lower = items.startIndex
            var upper = items.endIndex
            while lower < upper {
                let mid = (lower + upper) / 2
                if isOrdered(items[mid], before: item) {
                    lower = mid + 1
                } else {
                    upper = mid
                }
            }
            items.insert(item, at: lower)
        }
    }

    private func isOrdered(_ lhs: TranscriptItem, before rhs: TranscriptItem) -> Bool {
        lhs.sequence < rhs.sequence || (lhs.sequence == rhs.sequence && lhs.id < rhs.id)
    }

    /// Mirrors rc.2 `resultText`: each text content block stays verbatim, every
    /// non-text block is rendered as its own pretty JSON object, and parts retain
    /// their original order with one newline between them. An empty result uses
    /// only a Host-provided `name: code` error fallback.
    private func resultText(
        in message: [String: JSONValue],
        errorName: String?,
        errorCode: String?
    ) -> String? {
        let parts = (message["content"]?.arrayValue ?? []).compactMap { block -> String? in
            if let object = block.objectValue,
               object["type"]?.stringValue == "text",
               let text = object["text"]?.stringValue {
                return text
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            guard let encoded = try? encoder.encode(block),
                  let rendered = String(data: encoded, encoding: .utf8)
            else { return nil }
            return rendered
        }
        return NativeToolResultTextPresentation.flatten(
            parts: parts,
            errorName: errorName,
            errorCode: errorCode
        )
    }

    /// Search-card recovery mirrors `flattenContent`: only valid text blocks
    /// participate, in original order; an empty joined value is absent.
    private func textResult(in message: [String: JSONValue]) -> String? {
        let text = (message["content"]?.arrayValue ?? []).compactMap { block -> String? in
            guard let object = block.objectValue,
                  object["type"]?.stringValue == "text",
                  let value = object["text"]?.stringValue
            else { return nil }
            return value
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// Source: `sessions.schema.ts:contentBlockSchema`; the native transcript
    /// intentionally exposes only the text branch until image/tool adapters land.
    private func textContent(in value: JSONValue) -> String? {
        guard let content = value.objectValue?["content"]?.arrayValue else { return nil }
        let text = content.compactMap { block -> String? in
            guard let object = block.objectValue, object["type"]?.stringValue == "text" else { return nil }
            return object["text"]?.stringValue
        }.joined()
        return text.isEmpty ? nil : text
    }

    // TODO(perf): hot path — add JSONValue: Decodable to avoid encode→decode round-trip.
    private func decode<Value: Decodable>(_ type: Value.Type, from value: JSONValue) -> Value? {
        guard let data = try? Self.jsonEncoder.encode(value) else { return nil }
        return try? Self.jsonDecoder.decode(Value.self, from: data)
    }
}

private extension SessionPromptContent {
    var remotePromptContentPart: RemotePromptContentPart {
        switch self {
        case let .text(text):
            return .text(text)
        case let .image(mediaType, data, name):
            return .image(mediaType: mediaType, data: data, name: name)
        }
    }

    var remoteJSONValue: RemoteJSONValue {
        switch self {
        case let .text(text):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .image(mediaType, data, name):
            var object: [String: RemoteJSONValue] = [
                "type": .string("image"),
                "mediaType": .string(mediaType),
                "data": .string(data),
            ]
            if let name { object["name"] = .string(name) }
            return .object(object)
        }
    }
}

private extension SessionQueueAction {
    var remoteQueueAction: RemoteQueueAction {
        switch self {
        case let .edit(content): .edit(content: content.map(\.remoteJSONValue))
        case .remove: .remove
        case .steer: .steer
        }
    }

    var failureKind: NativeSessionStore.QueueActionFailure.Kind {
        switch self {
        case .edit: .edit
        case .remove: .remove
        case .steer: .steer
        }
    }
}
