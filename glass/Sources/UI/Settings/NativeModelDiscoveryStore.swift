import Combine

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Ephemeral model discovery state. A discovery request, including any optional
/// API key, is never retained; only the Host-returned candidate metadata is
/// observable after the call returns.
@MainActor
final class NativeModelDiscoveryStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case empty
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var candidates: [LLMDiscoveredModelDTO] = []

    func discover(_ request: LLMDiscoverModelsRequest, using api: (any NativeLLMDirectoryAPI)?) async {
        guard let api else {
            phase = .idle
            candidates = []
            return
        }
        phase = .loading
        candidates = []
        do {
            let response = try await api.discoverModels(request)
            candidates = response.models
            phase = candidates.isEmpty ? .empty : .ready
        } catch {
            // Discovery refusal/transport detail is not observable UI state;
            // model-directory failures remain Host-authoritative elsewhere.
            phase = .failed
        }
    }

    func dismiss() {
        candidates = []
        phase = .idle
    }
}
