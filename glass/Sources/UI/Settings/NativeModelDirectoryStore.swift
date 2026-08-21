import Combine

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Observable Host directory for the Models settings page. The store never
/// maintains a client-side provider catalog: every visible provider, group, and
/// failure comes from the current typed Host response.
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
            async let providerResponse = api.providers()
            async let modelResponse = api.models()
            let (providerDirectory, modelDirectory) = try await (providerResponse, modelResponse)
            // Preserve response ordering: a native sort would incorrectly
            // substitute client preference for Host directory authority.
            providers = providerDirectory.providers
            groups = modelDirectory.groups
            failures = NativeModelDirectoryFailurePresentation.project(modelDirectory.failures)
            phase = .ready
        } catch {
            providers = []
            groups = []
            failures = []
            phase = .failed
        }
    }
}
