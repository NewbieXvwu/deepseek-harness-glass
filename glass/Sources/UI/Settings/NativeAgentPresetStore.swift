import Combine

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Host-authoritative agent-preset roster used by Settings and new-session
/// surfaces. The native client never synthesizes a preset, its composition, or
/// a selected value: copy/delete/select settle only after the typed Host facade
/// answers and roster facts are refreshed.
@MainActor
final class NativeAgentPresetStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case unavailable
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var presets: [AgentPresetEntryDTO] = []
    @Published private(set) var authorable = false
    @Published private(set) var hasDocument = false
    @Published private(set) var selectedPreset: String?
    /// Preset-directory paths supplied by `agentPreset.openDocument` when the
    /// Host cannot open them itself. These remain Host text, not local URLs.
    @Published private(set) var revealedPaths: [String: String] = [:]
    /// The exact Host-returned read-only composition. It is cleared before a
    /// different roster replaces its row and is never manufactured from list data.
    @Published private(set) var detail: AgentPresetReadResponse?

    func refresh(using api: (any NativeAgentPresetAPI)?) async {
        guard let api else {
            reset()
            return
        }
        phase = .loading
        do {
            let response = try await api.list()
            presets = response.presets
            authorable = response.authorable
            hasDocument = response.hasDocument
            if let selectedPreset, !presets.contains(where: { $0.id == selectedPreset }) {
                self.selectedPreset = nil
            }
            if let detail, !presets.contains(where: { $0.id == detail.agentPreset }) {
                self.detail = nil
            }
            revealedPaths = revealedPaths.filter { presetID, _ in presets.contains(where: { $0.id == presetID }) }
            phase = presets.isEmpty ? .unavailable : .ready
        } catch {
            // A failed roster fetch cannot retain stale rows as Host facts.
            presets = []
            authorable = false
            hasDocument = false
        selectedPreset = nil
        revealedPaths = [:]
        detail = nil
        phase = .failed
        }
    }

    /// Loads one composition only from the Host. A mismatched response is not
    /// surfaced because it cannot be associated safely with the selected row.
    @discardableResult
    func read(agentPreset: String, using api: (any NativeAgentPresetAPI)?) async -> Bool {
        guard let api, presets.contains(where: { $0.id == agentPreset }) else { return false }
        do {
            let response = try await api.read(agentPreset: agentPreset)
            guard response.agentPreset == agentPreset else { return false }
            detail = response
            return true
        } catch {
            return false
        }
    }

    func dismissDetail() {
        detail = nil
    }

    /// Delegates all document-opening behavior to the Host. Native state is
    /// updated only for the explicit non-opened path response the Host returns.
    @discardableResult
    func openDocument(agentPreset: String, using api: (any NativeAgentPresetAPI)?) async -> Bool {
        guard let api, presets.contains(where: { $0.id == agentPreset }) else { return false }
        do {
            let response = try await api.openDocument(agentPreset: agentPreset)
            if response.opened { return true }
            guard let path = response.path, !path.isEmpty else { return false }
            revealedPaths[agentPreset] = path
            return true
        } catch {
            return false
        }
    }

    /// Creates a preset solely through a Host-side copy then reloads the whole
    /// directory, matching RC8's roster-re-read contract.
    @discardableResult
    func copy(_ request: AgentPresetCopyRequest, using api: (any NativeAgentPresetAPI)?) async -> Bool {
        guard let api, presets.contains(where: { $0.id == request.from }) else { return false }
        do {
            let response = try await api.copy(request)
            guard response.agentPreset == request.agentPreset else { return false }
            await refresh(using: api)
            return presets.contains(where: { $0.id == request.agentPreset })
        } catch {
            return false
        }
    }

    /// Removes a preset only after the Host accepts it, then reloads every row
    /// rather than locally deleting one entry from a possibly changed roster.
    @discardableResult
    func remove(agentPreset: String, using api: (any NativeAgentPresetAPI)?) async -> Bool {
        guard let api, presets.contains(where: { $0.id == agentPreset }) else { return false }
        do {
            _ = try await api.remove(agentPreset: agentPreset)
            await refresh(using: api)
            return !presets.contains(where: { $0.id == agentPreset })
        } catch {
            return false
        }
    }

    /// Stages the Host-confirmed preset for the supplied session. The returned
    /// id must still be present and selectable in the current roster; otherwise
    /// no local selection claim is made.
    @discardableResult
    func select(sessionID: String, agentPreset: String, using api: (any NativeAgentPresetAPI)?) async -> Bool {
        guard let api else { return false }
        do {
            let response = try await api.select(sessionID: sessionID, agentPreset: agentPreset)
            guard presets.contains(where: { $0.id == response.agentPreset && $0.broken == nil }) else { return false }
            selectedPreset = response.agentPreset
            return true
        } catch {
            return false
        }
    }

    private func reset() {
        phase = .idle
        presets = []
        authorable = false
        hasDocument = false
        selectedPreset = nil
        revealedPaths = [:]
        detail = nil
    }
}
