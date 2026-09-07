import Combine

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

extension LLMController: NativeLLMDirectoryAPI {}

/// Observable Host directory for the Models settings page. RC.1 owns the
/// provider directory through the joined configurable/live provider responses;
/// legacy model-group and failure seats remain empty in this build.
@MainActor
final class NativeModelDirectoryStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var providers: [LLMProviderDTO] = []
    @Published private(set) var groups: [LLMModelGroupDTO] = []
    @Published private(set) var failures: [NativeModelDirectoryFailurePresentation] = []

    func refresh(using api: (any NativeLLMDirectoryAPI)?) async {
        guard let api else {
            phase = .idle
            providers = []
            groups = []
            failures = []
            return
        }
        phase = .loading
        do {
            let providerDirectory = try await api.providers()
            // RC.1 settings models renders the joined configurable/live provider
            // directory. There is no Remote `llm/models` authority in this build.
            providers = providerDirectory.providers
            groups = []
            failures = []
            phase = .ready
        } catch {
            providers = []
            groups = []
            failures = []
            phase = .failed
        }
    }
}
