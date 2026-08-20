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
    func models(sessionID: String) async throws -> SessionModelsResponse
    func answerApproval(rpcID: String, sessionID: String, approvalID: String, outcome: ApprovalOutcome) async throws -> RPCReceipt
    func answerQuestion(rpcID: String, sessionID: String, answers: [QuestionAnswerResponse]) async throws -> RPCReceipt
    func cancelQuestion(rpcID: String) async throws -> RPCReceipt
}

extension SessionsAPI: NativeSessionAPI {}

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
    enum Phase: Equatable {
        case idle
        case loading(sessionID: String)
        case ready(sessionID: String)
        case failed(sessionID: String)
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
    /// Source: `events.schema.ts:approval/requested`; rpcID is the stable
    /// answerable ServerRequest correlation identity and must be echoed on
    /// `/api/respond`, while approvalID identifies the business request.
    struct PendingApproval: Identifiable, Equatable {
        let rpcID: String
        let sessionID: String
        let approvalID: String
        let toolName: String
        let callID: String?
        let reason: String?

        var id: String { approvalID }
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
            let intent: Intent? = nil
        }

        let rpcID: String
        let sessionID: String
        let items: [Item]

        var id: String { rpcID }
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
        var state: State
        let sequence: Int
        var view: JSONValue?
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
        let role: String
        let content: [JSONValue]
        let source: JSONValue
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
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var isLoadingOlderHistory = false
    @Published private(set) var isRunning = false
    /// RC8 `ChatStoreState.view`: a retained id may be stale after a plugin
    /// unload, so UI resolves it through the stable Chat fallback.
    @Published private(set) var selectedViewID: String?
    @Published private(set) var isSubmittingPrompt = false
    @Published var draft = ""
    @Published private(set) var pendingImages: [PendingImage] = []
    @Published private(set) var toolInvocations: [ToolInvocation] = []
    @Published private(set) var queuedMessages: [QueuedMessage] = []
    @Published private(set) var backgroundJobs: [BackgroundJob] = []
    /// The per-session Host `session.models` authority. A nil value means it has
    /// not been loaded or the current session cannot be restored yet; it is not
    /// an invitation to invent a default provider/model pair.
    @Published private(set) var modelDirectory: CoreSessionModelDirectory?
    @Published private(set) var selectedToolCallID: String?
    @Published private(set) var pendingApproval: PendingApproval?
    @Published private(set) var pendingQuestion: PendingQuestion?
    @Published private(set) var isSubmittingApproval = false
    @Published private(set) var isSubmittingQuestion = false
    @Published private(set) var lastError: DSHTransportError?

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
    private var promptTask: Task<Void, Never>?
    private var cancelTask: Task<Void, Never>?
    private var olderHistoryTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    /// A recovery is distinct from initial history loading. Its monotonic token
    /// prevents an old Host generation, endpoint, or selected session from
    /// applying models/history/projections after a newer authority request.
    private var recoveryTask: Task<Void, Never>?
    private var recoveryGeneration: UInt = 0
    private var endpoint: URL?
    private var api: (any NativeSessionAPI)?
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

    /// Source: RC8 `SessionProjectionMap.imageLimits`. Absence means the Host
    /// has no composed attachment service, so UI callers do not invent limits
    /// and allow the authoritative prompt admission result to decide.
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
        sessionCWD: String? = nil
    ) {
        guard activeSessionID != sessionID || self.endpoint != endpoint else { return }
        preserveActiveState()
        historyTask?.cancel()
        olderHistoryTask?.cancel()
        promptTask?.cancel()
        cancelTask?.cancel()
        streamTask?.cancel()
        recoveryTask?.cancel()
        recoveryGeneration &+= 1
        let authorityGeneration = recoveryGeneration
        self.api = api
        self.hostPathAPI = hostPathAPI
        self.activeSessionCWD = sessionCWD
        self.endpoint = endpoint
        activeSessionID = sessionID
        let restoredResident = restoreResidentState(for: sessionID)
        if !restoredResident {
            items = []
            resetConversationWindow()
            toolInvocations = []
            queuedMessages = []
            backgroundJobs = []
            modelDirectory = nil
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

        historyTask = Task { [weak self] in
            do {
                // The locked Host's `agentFor` resolver is the official
                // read-only cold-resume path. After a Host restart, models()
                // reattaches a persisted selected session before mux opens;
                // history() alone intentionally serves detached logs.
                let models = try await api.models(sessionID: sessionID)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == authorityGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                self?.modelDirectory = .init(response: models)
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
                self?.observeMux(sessionID: sessionID, endpoint: endpoint)
            } catch let error as DSHTransportError {
                guard !Task.isCancelled,
                      self?.recoveryGeneration == authorityGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                self?.lastError = error
                if !restoredResident { self?.phase = .failed(sessionID: sessionID) }
            } catch {
                guard !Task.isCancelled,
                      self?.recoveryGeneration == authorityGeneration,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                if !restoredResident { self?.phase = .failed(sessionID: sessionID) }
            }
        }
    }

    func disconnect() {
        historyTask?.cancel()
        historyTask = nil
        olderHistoryTask?.cancel()
        olderHistoryTask = nil
        streamTask?.cancel()
        streamTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryGeneration &+= 1
        endpoint = nil
        api = nil
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
        guard let mediaType = Self.mediaType(for: url),
              let data = try? Data(contentsOf: url)
        else { return }
        pendingImages.append(PendingImage(
            id: UUID(),
            name: url.lastPathComponent,
            mediaType: mediaType,
            data: data
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
              let api,
              let sessionID = activeSessionID
        else { return }

        isSubmittingPrompt = true
        promptTask?.cancel()
        promptTask = Task { [weak self] in
            defer { self?.isSubmittingPrompt = false }
            do {
                let response = try await api.prompt(sessionID: sessionID, content: content, mode: .queue)
                guard !Task.isCancelled, response.accepted, self?.activeSessionID == sessionID else { return }
                self?.draft = ""
                self?.pendingImages = []
            } catch {
                // The draft remains available after a rejected prompt, matching
                // the official composer retry posture. Prompt-error presentation
                // is added with the attachment/notice surface.
            }
        }
    }

    /// Source: `sessions.schema.ts:sessionCancelRequestSchema`.
    func cancelRunningTurn() {
        guard isRunning, let api, let sessionID = activeSessionID else { return }
        cancelTask?.cancel()
        cancelTask = Task {
            _ = try? await api.cancel(sessionID: sessionID)
        }
    }

    /// Source: `sessions.schema.ts:sessionHistoryRequestSchema`. The Host owns
    /// message-boundary paging and returns the authority for `hasMore`.
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
                let response = try await api.history(sessionID: sessionID, beforeSeq: beforeSeq, maxMessages: nil)
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.prependConversationWindow(response.events.map(ConversationEventInput.init(entry:)), hasMore: response.hasMore)
                self?.applyHistory(response.events)
                if let projections = response.projections { self?.projections.seed(sessionID: sessionID, baseline: projections) }
                self?.hasMoreHistory = response.hasMore
            } catch {
                // Retain the existing official transcript if a backward page
                // fails; a templated error surface follows transport code mapping.
            }
        }
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
    }

    private func replaceConversationWindow(_ entries: [ConversationEventInput], hasMore: Bool) {
        conversationReducer = ConversationNodeReducer(
            definitions: ConversationCoreNodeRegistry.initialDefinitions()
        )
        _ = conversationReducer.replaceWindow(entries, hasMore: hasMore)
        chatNodes = conversationReducer.snapshot(target: "chat")
    }

    private func prependConversationWindow(_ entries: [ConversationEventInput], hasMore: Bool) {
        _ = conversationReducer.prepend(entries, hasMore: hasMore)
        chatNodes = conversationReducer.snapshot(target: "chat")
    }

    private func appendConversationEvent(_ input: ConversationEventInput) {
        _ = conversationReducer.append(input)
        chatNodes = conversationReducer.snapshot(target: "chat")
    }

    private func applyHistory(_ entries: [SessionHistoryEntryDTO]) {
        for entry in entries.sorted(by: { $0.event.seq < $1.event.seq }) {
            apply(event: entry.event, view: entry.view?.view)
        }
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
            guard !liveEventRequiresAuthorityRecovery(event) else {
                requestAuthorityRecovery(sessionID: sessionID, reason: .eventGap)
                return
            }
            let view = object["view"].flatMap { decode(ToolEventViewDTO.self, from: $0) }
            appendConversationEvent(.init(event: event, view: view))
            apply(event: event, view: view?.view)
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
        projections.truncate(sessionID: sessionID, after: subscribed.lastSeq)
        queuedMessages = []
        backgroundJobs = []
        // approval/question ServerRequests are generation-bound, exactly like
        // queue/jobs. A restarted Host can no longer resolve an old rpcId; keep
        // no stale takeover visible until the fresh mux baseline re-emits it.
        pendingApproval = nil
        pendingQuestion = nil
        isSubmittingApproval = false
        isSubmittingQuestion = false
        if let priorWindowHighWatermark, subscribed.lastSeq < priorWindowHighWatermark {
            requestAuthorityRecovery(sessionID: sessionID, reason: .subscriptionWatermark)
        }
    }

    private enum AuthorityRecoveryReason {
        case eventGap
        case subscriptionWatermark
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
        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        recoveryTask = Task { [weak self] in
            do {
                let models = try await api.models(sessionID: sessionID)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                let history = try await api.history(sessionID: sessionID, beforeSeq: nil, maxMessages: nil)
                guard !Task.isCancelled,
                      self?.recoveryGeneration == generation,
                      self?.activeSessionID == sessionID,
                      self?.endpoint == endpoint
                else { return }
                self?.modelDirectory = .init(response: models)
                self?.replaceConversationWindow(history.events.map(ConversationEventInput.init(entry:)), hasMore: history.hasMore)
                self?.items = []
                self?.appliedSequences = []
                self?.applyHistory(history.events)
                if let projections = history.projections {
                    self?.projections.seed(sessionID: sessionID, baseline: projections)
                }
                self?.hasMoreHistory = history.hasMore
                self?.phase = .ready(sessionID: sessionID)
            } catch {
                // Keep the last complete authority window visible. A newer
                // mux/recovery generation or a finite stream failure owns any
                // user-facing transport error policy; stale recovery errors do
                // not replace a selected resident transcript.
            }
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
        isSubmittingApproval = false
    }

    private func applyQuestionRequest(_ object: [String: JSONValue], rpcID: String, sessionID: String) {
        guard let values = object["questions"]?.arrayValue else { return }
        let items = values.compactMap(questionItem)
        guard !items.isEmpty, items.count == values.count else { return }
        guard pendingQuestion?.rpcID != rpcID else { return }
        pendingQuestion = PendingQuestion(rpcID: rpcID, sessionID: sessionID, items: items)
        isSubmittingQuestion = false
    }

    private func applyQuestionResolution(_ object: [String: JSONValue]) {
        guard let rpcID = object["questionRpcId"]?.stringValue,
              pendingQuestion?.rpcID == rpcID
        else { return }
        pendingQuestion = nil
        isSubmittingQuestion = false
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

    /// Source: `PendingApproval.answer`; a panel remains mounted until the Host
    /// broadcasts `approval/resolved`, even after an accepted carrier receipt.
    func answerApproval(allowOnce: Bool) {
        guard let approval = pendingApproval,
              let api,
              !isSubmittingApproval
        else { return }
        isSubmittingApproval = true
        let outcome: ApprovalOutcome = allowOnce ? .allowedOnce : .rejected
        Task { [weak self] in
            do {
                let receipt = try await api.answerApproval(
                    rpcID: approval.rpcID,
                    sessionID: approval.sessionID,
                    approvalID: approval.approvalID,
                    outcome: outcome
                )
                guard !Task.isCancelled, !receipt.accepted else { return }
                self?.isSubmittingApproval = false
            } catch {
                self?.isSubmittingApproval = false
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
        Task { [weak self] in
            do {
                let receipt = try await api.answerQuestion(rpcID: question.rpcID, sessionID: question.sessionID, answers: responseAnswers)
                guard !Task.isCancelled, !receipt.accepted else { return }
                self?.isSubmittingQuestion = false
            } catch {
                self?.isSubmittingQuestion = false
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
        Task { [weak self] in
            do {
                let receipt = try await api.cancelQuestion(rpcID: question.rpcID)
                guard !Task.isCancelled, !receipt.accepted else { return }
                self?.isSubmittingQuestion = false
            } catch {
                self?.isSubmittingQuestion = false
            }
        }
    }

    private func apply(event: SessionEventDTO, view: JSONValue? = nil) {
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
            applyToolCall(event, view: view)
        case "tool/result":
            applyToolResult(event, view: view)
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

    private func applyToolCall(_ event: SessionEventDTO, view: JSONValue?) {
        guard let data = event.data.objectValue,
              let callID = data["callId"]?.stringValue,
              let name = data["name"]?.stringValue,
              let arguments = data["arguments"]?.stringValue
        else { return }
        guard !toolInvocations.contains(where: { $0.id == callID }) else { return }
        toolInvocations.append(ToolInvocation(
            id: callID,
            name: name,
            arguments: arguments,
            output: nil,
            state: .running,
            sequence: event.seq,
            view: view
        ))
        toolInvocations.sort { $0.sequence < $1.sequence }
    }

    private func applyToolResult(_ event: SessionEventDTO, view: JSONValue?) {
        guard let data = event.data.objectValue,
              let message = data["message"]?.objectValue,
              let source = message["source"]?.objectValue,
              let callID = source["callId"]?.stringValue
        else { return }
        let errorCode = data["error"]?.objectValue?["code"]?.stringValue
        let output = textContent(in: .object(message)) ?? prettyContent(in: message)
        guard let index = toolInvocations.firstIndex(where: { $0.id == callID }) else { return }
        toolInvocations[index].output = output
        toolInvocations[index].state = errorCode == "interrupted" ? .stopped : (errorCode == nil ? .completed : .failed)
        toolInvocations[index].view = view ?? toolInvocations[index].view
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
                state: .completed,
                sequence: 102,
                view: nil
            ),
            ToolInvocation(
                id: "snapshot-bash",
                name: "bash",
                arguments: "pwd",
                output: nil,
                state: .running,
                sequence: 103,
                view: nil
            )
        ]
        queuedMessages = []
        backgroundJobs = []
        modelDirectory = nil
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

    private func settleStreaming() {
        for index in items.indices where items[index].isStreaming {
            items[index].isStreaming = false
        }
    }

    private func upsert(_ item: TranscriptItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
            items.sort { $0.sequence < $1.sequence || ($0.sequence == $1.sequence && $0.id < $1.id) }
        }
    }

    private func prettyContent(in message: [String: JSONValue]) -> String? {
        guard let content = message["content"]?.arrayValue,
              let data = try? JSONEncoder().encode(content),
              let rendered = String(data: data, encoding: .utf8),
              !rendered.isEmpty
        else { return nil }
        return rendered
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

    private static func mediaType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return nil
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from value: JSONValue) -> Value? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
