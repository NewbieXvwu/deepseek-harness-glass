import Foundation

struct LLMController: Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func providers() async throws -> LLMProvidersResponse {
        async let registered: [ProviderInfo] = remote.call(
            RemoteProcedure(.llmListProviders),
            arguments: EmptyArguments()
        )
        async let configurable: [ConfigurableProvider] = remote.call(
            RemoteProcedure(.llmListConfigurableProviders),
            arguments: EmptyArguments()
        )
        let (live, directory) = try await (registered, configurable)
        let active = Set(live.map(\.id))
        let declared = Set(directory.map(\.provider))
        var rows = directory.map { entry in
            LLMProviderDTO(
                provider: entry.provider,
                displayName: entry.displayName,
                settingsNs: entry.settingsNs,
                settingsPath: entry.settingsPath,
                active: active.contains(entry.provider),
                declared: entry.declared
            )
        }
        rows.append(contentsOf: live.compactMap { provider in
            guard !declared.contains(provider.id) else { return nil }
            return LLMProviderDTO(
                provider: provider.id,
                displayName: provider.name,
                settingsNs: "",
                settingsPath: [],
                active: true,
                declared: nil
            )
        })
        return LLMProvidersResponse(providers: rows)
    }

    func discoverModels(_ request: LLMDiscoverModelsRequest) async throws -> LLMDiscoverModelsResponse {
        let models: [LLMDiscoveredModelDTO] = try await remote.call(
            RemoteProcedure(.llmDiscoverModels),
            arguments: DiscoverArguments(
                settingsNs: request.settingsNs,
                request: DiscoveryRequest(
                    provider: request.provider,
                    baseURL: request.baseURL,
                    api: request.api,
                    apiKey: request.apiKey
                )
            )
        )
        return LLMDiscoverModelsResponse(models: models)
    }

    private struct EmptyArguments: Codable, Sendable {}

    private struct ProviderInfo: Codable, Sendable {
        let id: String
        let name: String
    }

    private struct ConfigurableProvider: Codable, Sendable {
        let provider: String
        let displayName: String
        let settingsNs: String
        let settingsPath: [String]
        let declared: Bool?
    }

    private struct DiscoveryRequest: Codable, Sendable {
        let provider: String?
        let baseURL: String?
        let api: String?
        let apiKey: String?
    }

    private struct DiscoverArguments: Codable, Sendable {
        let settingsNs: String
        let request: DiscoveryRequest
    }
}
