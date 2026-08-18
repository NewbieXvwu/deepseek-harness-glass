import AppKit
import Combine
import Foundation

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
        let sequence: Int
    }

    /// Source: `sessions.schema.ts:promptContentPartSchema`. This is transient
    /// composer state only; durable attachment identities remain Host-owned.
    struct PendingImage: Identifiable {
        let id: UUID
        let name: String
        let mediaType: String
        let data: Data
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [TranscriptItem] = []
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var isLoadingOlderHistory = false
    @Published private(set) var isRunning = false
    @Published private(set) var isSubmittingPrompt = false
    @Published var draft = ""
    @Published private(set) var pendingImages: [PendingImage] = []
    @Published private(set) var lastError: DSHTransportError?

    private var historyTask: Task<Void, Never>?
    private var promptTask: Task<Void, Never>?
    private var cancelTask: Task<Void, Never>?
    private var olderHistoryTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var endpoint: URL?
    private var api: DSHAPIClient?
    private var activeSessionID: String?
    private var appliedSequences: Set<Int> = []

    deinit {
        historyTask?.cancel()
        olderHistoryTask?.cancel()
        promptTask?.cancel()
        cancelTask?.cancel()
        streamTask?.cancel()
    }

    /// Opens one selected Host session. The existing view remains mounted while
    /// a new history baseline loads, mirroring the official resident scrollport.
    func open(sessionID: String, using api: DSHAPIClient, endpoint: URL) {
        guard activeSessionID != sessionID || self.endpoint != endpoint else { return }
        historyTask?.cancel()
        olderHistoryTask?.cancel()
        promptTask?.cancel()
        cancelTask?.cancel()
        streamTask?.cancel()
        self.api = api
        self.endpoint = endpoint
        activeSessionID = sessionID
        items = []
        appliedSequences = []
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isRunning = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
        phase = .loading(sessionID: sessionID)

        historyTask = Task { [weak self] in
            do {
                let response = try await api.sessionHistory(sessionID: sessionID)
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.applyHistory(response.events)
                self?.hasMoreHistory = response.hasMore
                self?.phase = .ready(sessionID: sessionID)
                self?.observeMux(sessionID: sessionID, endpoint: endpoint)
            } catch let error as DSHTransportError {
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.lastError = error
                self?.phase = .failed(sessionID: sessionID)
            } catch {
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.phase = .failed(sessionID: sessionID)
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
        endpoint = nil
        api = nil
        activeSessionID = nil
        phase = .idle
        items = []
        appliedSequences = []
        hasMoreHistory = false
        isLoadingOlderHistory = false
        isRunning = false
        isSubmittingPrompt = false
        draft = ""
        pendingImages = []
        lastError = nil
    }

    /// Uses the native macOS file panel. The Host remains responsible for final
    /// attachment validation at submit; this store only accepts the official
    /// raster media types declared by `imageMediaTypeSchema`.
    func choosePendingImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addPendingImage)
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
                let response = try await api.sessionPrompt(sessionID: sessionID, content: content, mode: .queue)
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
            _ = try? await api.sessionCancel(sessionID: sessionID)
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
                let response = try await api.sessionHistory(sessionID: sessionID, beforeSeq: beforeSeq)
                guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                self?.applyHistory(response.events)
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
            let stream = await client.stream(.mux)
            do {
                for try await frame in stream {
                    guard !Task.isCancelled, self?.activeSessionID == sessionID else { return }
                    self?.applyMuxFrame(frame, sessionID: sessionID)
                }
            } catch is CancellationError {
                return
            } catch {
                // The official reconnection posture is reopen + refetch history.
                // Lifecycle recovery owns retries; stale partial transcript remains
                // readable until the next verified endpoint transition.
            }
        }
    }

    private func applyHistory(_ entries: [SessionHistoryEntryDTO]) {
        for entry in entries.sorted(by: { $0.event.seq < $1.event.seq }) {
            apply(event: entry.event)
        }
    }

    /// Source: `events.ts:MuxFrame` uses frame.method as the event discriminant
    /// in the native SSE transport's server-request envelope.
    private func applyMuxFrame(_ frame: RPCServerRequest, sessionID: String) {
        guard frame.method == "session/event",
              let object = frame.payload.objectValue,
              object["sessionId"]?.stringValue == sessionID,
              let eventValue = object["event"],
              let event = decode(SessionEventDTO.self, from: eventValue)
        else { return }
        apply(event: event)
    }

    private func apply(event: SessionEventDTO) {
        if event.type != "assistant/chunk" {
            guard appliedSequences.insert(event.seq).inserted else { return }
        }

        switch event.type {
        case "user/message":
            guard let text = textContent(in: event.data) else { return }
            upsert(TranscriptItem(
                id: "event-\(event.seq)",
                role: .user,
                text: text,
                isStreaming: false,
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
                sequence: event.seq
            ))
        case "turn/start":
            isRunning = true
        case "assistant/chunk":
            isRunning = true
            applyAssistantChunk(event)
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
                sequence: event.seq
            ))
        }
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

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }
}
