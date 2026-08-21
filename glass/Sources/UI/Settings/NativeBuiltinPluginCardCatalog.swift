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

    static func dispatched(from namespaces: [SettingsNamespaceDTO]) -> [Self] {
        let served = Set(namespaces.map(\.ns))
        return allCases.filter { served.contains($0.namespace) }
    }

    private static func official(_ key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-plugins", key: key, language: "en") ?? ""
    }
}
