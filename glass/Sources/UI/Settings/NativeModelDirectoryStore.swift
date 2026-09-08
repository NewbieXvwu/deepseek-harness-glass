import Combine

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

extension LLMController: NativeLLMDirectoryAPI {}

/// Observable Host directory for the Models settings page. RC.1 owns the
/// provider directory through the joined configurable/live provider responses.
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

    func refresh(using api: (any NativeLLMDirectoryAPI)?) async {
        guard let api else {
            phase = .idle
            providers = []
            return
        }
        phase = .loading
        do {
            let providerDirectory = try await api.providers()
            providers = providerDirectory.providers
            phase = .ready
        } catch {
            providers = []
            phase = .failed
        }
    }
}
