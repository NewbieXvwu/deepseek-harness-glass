#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Joins a Host provider directory row with the already-described Settings
/// authority. The profile's resolved `apiKeyEnv` is the only credential
/// reference safe to display for an existing route; absent/malformed profiles
/// never cause a native fallback reference to be invented.
enum NativeProviderCredentialReferencePresentation {
    static func reference(
        for provider: LLMProviderDTO,
        namespaces: [SettingsNamespaceDTO]
    ) -> String? {
        guard let namespace = namespaces.first(where: { $0.ns == provider.settingsNs }),
              let profile = value(at: provider.settingsPath, in: namespace.value).objectValue,
              let reference = profile["apiKeyEnv"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reference.isEmpty
        else { return nil }
        return reference
    }

    static func references(
        for providers: [LLMProviderDTO],
        namespaces: [SettingsNamespaceDTO]
    ) -> [String] {
        var seen = Set<String>()
        return providers.compactMap { reference(for: $0, namespaces: namespaces) }
            .filter { seen.insert($0).inserted }
    }

    private static func value(at path: [String], in root: JSONValue) -> JSONValue? {
        path.reduce(root) { partial, key in
            partial?.objectValue?[key]
        }
    }
}
