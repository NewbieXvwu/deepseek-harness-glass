#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// The three built-in configurable cards shipped by the locked official
/// `ui-settings-plugins` package. A card is dispatched only when its Host
/// namespace is currently served; unknown namespaces belong to another owner.
enum NativeBuiltinPluginCard: CaseIterable, Identifiable, Equatable {
    case bash
    case agentLoop
    case webSearch

    var id: String { namespace }

    var namespace: String {
        switch self {
        case .bash: "shell"
        case .agentLoop: "agent-loop"
        case .webSearch: "web-search-deepseek"
        }
    }

    var title: String {
        switch self {
        case .bash: NativeBuiltinPluginCard.official("bashTitle")
        case .agentLoop: NativeBuiltinPluginCard.official("agentLoopTitle")
        case .webSearch: NativeBuiltinPluginCard.official("webSearchTitle")
        }
    }

    var description: String {
        switch self {
        case .bash: NativeBuiltinPluginCard.official("bashDescription")
        case .agentLoop: NativeBuiltinPluginCard.official("agentLoopDescription")
        case .webSearch: NativeBuiltinPluginCard.official("webSearchDescription")
        }
    }

    /// Fields are the exact native controls owned by the locked official cards.
    /// The web-search API key is intentionally absent: it uses the write-only
    /// credentials domain rather than a settings-section operation.
    var fields: [NativePluginCardField] {
        switch self {
        case .bash:
            [
                .init("timeoutMs", kind: .number),
                .init("maxOutputBytes", kind: .number),
            ]
        case .agentLoop:
            [.init("maxParallelToolCalls", kind: .number)]
        case .webSearch:
            [
                .init("baseURL", kind: .text),
                .init("maxUses", kind: .number),
            ]
        }
    }

    static func dispatched(from namespaces: [SettingsNamespaceDTO]) -> [Self] {
        let served = Set(namespaces.map(\.ns))
        return allCases.filter { served.contains($0.namespace) }
    }

    private static func official(_ key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-plugins", key: key, language: "en") ?? ""
    }
}
