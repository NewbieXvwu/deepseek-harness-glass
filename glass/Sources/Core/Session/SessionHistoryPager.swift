import Combine
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Host-authoritative raw session-history window.
///
/// This is the Swift equivalent of the locked Web runtime's `Session.events`
/// paging slice. It never folds business nodes: the window contains every raw
/// `SessionHistoryEntryDTO`, including compaction summaries, replacement
/// boundaries and otherwise invisible events. Conversation assembly consumes
/// this contiguous range in T6.4+.
@MainActor
final class SessionHistoryPager: ObservableObject {
    /// Locked `packages/client/runtime/src/client/sessions/session.ts:PAGE_MESSAGES`.
    static let pageMessages = 50

    typealias HistoryLoader = (String, Int?, Int?) async throws -> SessionHistoryResponse

    enum TailState: Equatable {
        case cold
        case loading(sessionID: String)
        case ready(sessionID: String)
        case failed(sessionID: String, error: DSHTransportError)
    }

    enum OlderState: Equatable {
        case idle
        case loading(sessionID: String, beforeSeq: Int)
        case failed(sessionID: String, beforeSeq: Int, error: DSHTransportError)
    }

    enum LiveAcceptance: Equatable {
        case appended
        case duplicate
        case gap(expected: Int, received: Int)
        case cold
    }

    @Published private(set) var tailState: TailState = .cold
    @Published private(set) var olderState: OlderState = .idle
    @Published private(set) var entries: [SessionHistoryEntryDTO] = []
    @Published private(set) var hasMore = false
    @Published private(set) var projections: SessionProjectionsDTO?

    private var sessionID: String?
    private var loader: HistoryLoader?
    private var generation = 0

    var baseSeq: Int? { entries.first?.event.seq }
    var tailSeq: Int? { entries.last?.event.seq }
    var rawRange: ClosedRange<Int>? {
        guard let baseSeq, let tailSeq else { return nil }
        return baseSeq...tailSeq
    }
    var isLoadingOlder: Bool {
        if case .loading = olderState { return true }
        return false
    }

    /// Binds one Host session and invalidates all state only when identity or
    /// source changes. A session always has exactly one source of pagination.
    func bind(sessionID: String, loader: @escaping HistoryLoader) {
        guard self.sessionID != sessionID else {
            self.loader = loader
            return
        }
        generation += 1
        self.sessionID = sessionID
        self.loader = loader
        entries = []
        hasMore = false
        projections = nil
        tailState = .cold
        olderState = .idle
    }

    /// Drops one resident window. NativeSessionStore retains windows by Session
    /// ID separately; a disconnect must not keep Host-derived raw events alive.
    func reset() {
        generation += 1
        sessionID = nil
        loader = nil
        entries = []
        hasMore = false
        projections = nil
        tailState = .cold
        olderState = .idle
    }

    /// Pulls the message-boundary tail. It is safe to call repeatedly after an
    /// error; an in-flight tail pull is coalesced by the explicit loading state.
    @discardableResult
    func loadTail(maxMessages: Int = SessionHistoryPager.pageMessages) async -> Bool {
        guard let sessionID, let loader else { return false }
        if case .loading = tailState { return false }
        let callGeneration = generation
        tailState = .loading(sessionID: sessionID)
        do {
            let response = try await loader(sessionID, nil, maxMessages)
            guard callGeneration == generation, self.sessionID == sessionID else { return false }
            try installTail(response)
            tailState = .ready(sessionID: sessionID)
            return true
        } catch {
            guard callGeneration == generation, self.sessionID == sessionID else { return false }
            tailState = .failed(sessionID: sessionID, error: transportError(from: error))
            return false
        }
    }

    /// Retries only the tail transport/error branch, retaining the same bound
    /// Host loader and exact official page size.
    @discardableResult
    func retryTail() async -> Bool {
        await loadTail()
    }

    /// Fetches the next earlier message-boundary page. A rejected, empty, or
    /// discontinuous page never mutates the existing raw window, preventing
    /// duplicate or out-of-order event insertion.
    @discardableResult
    func loadOlder(maxMessages: Int = SessionHistoryPager.pageMessages) async -> Bool {
        guard let sessionID, let loader, let beforeSeq = baseSeq, hasMore, !isLoadingOlder else { return false }
        let callGeneration = generation
        olderState = .loading(sessionID: sessionID, beforeSeq: beforeSeq)
        defer {
            if callGeneration == generation, self.sessionID == sessionID,
               case .loading = olderState {
                olderState = .idle
            }
        }
        do {
            let response = try await loader(sessionID, beforeSeq, maxMessages)
            guard callGeneration == generation, self.sessionID == sessionID else { return false }
            return try prepend(response)
        } catch {
            guard callGeneration == generation, self.sessionID == sessionID else { return false }
            olderState = .failed(sessionID: sessionID, beforeSeq: beforeSeq, error: transportError(from: error))
            return false
        }
    }

    /// Appends a live raw event only when it extends this page contiguously.
    /// Gap repair intentionally remains caller-driven: the caller pulls a fresh
    /// tail authority page instead of displaying a hole in the event log.
    @discardableResult
    func acceptLive(_ entry: SessionHistoryEntryDTO) -> LiveAcceptance {
        guard case .ready = tailState else { return .cold }
        guard let tailSeq else {
            entries = [entry]
            return .appended
        }
        if entry.event.seq <= tailSeq { return .duplicate }
        guard entry.event.seq == tailSeq + 1 else {
            return .gap(expected: tailSeq + 1, received: entry.event.seq)
        }
        entries.append(entry)
        return .appended
    }

    /// Session export uses the same authenticated Host session as Remote and
    /// mux. No history page or raw event is re-encoded locally.
    func export(
        authenticatedHost: AuthenticatedHostSession,
        exporter: SessionLogExporter,
        includeDescendants: Bool = true
    ) async throws -> SessionLogExport {
        guard let sessionID else { throw DSHTransportError.invalidEndpoint }
        return try await exporter.export(
            sessionID: sessionID,
            includeDescendants: includeDescendants,
            authenticatedHost: authenticatedHost
        )
    }

    private func installTail(_ response: SessionHistoryResponse) throws {
        entries = try normalized(response.events)
        hasMore = response.hasMore
        projections = response.projections
        olderState = .idle
    }

    private func prepend(_ response: SessionHistoryResponse) throws -> Bool {
        let older = try normalized(response.events)
        guard !older.isEmpty else {
            hasMore = response.hasMore
            return true
        }
        guard let currentBase = baseSeq,
              let olderTail = older.last?.event.seq,
              olderTail + 1 == currentBase
        else {
            // Match the locked Web fail-soft posture: retain the good window,
            // stop automatic earlier pulls, and expose a typed recoverable
            // integrity error for a retry/resync control instead of rendering a
            // non-contiguous conversation.
            hasMore = false
            if let sessionID, let beforeSeq = baseSeq {
                olderState = .failed(
                    sessionID: sessionID,
                    beforeSeq: beforeSeq,
                    error: .decoding("discontinuous session history page")
                )
            }
            return false
        }
        entries = older + entries
        hasMore = response.hasMore
        return true
    }

    private func normalized(_ candidates: [SessionHistoryEntryDTO]) throws -> [SessionHistoryEntryDTO] {
        var previous: Int?
        for entry in candidates {
            if let previous, entry.event.seq <= previous {
                throw DSHTransportError.decoding("duplicate or unordered session history event sequence")
            }
            previous = entry.event.seq
        }
        return candidates
    }

    private func transportError(from error: Error) -> DSHTransportError {
        if let error = error as? DSHTransportError { return error }
        if error is CancellationError { return .cancelled }
        return .network(error.localizedDescription)
    }
}
