#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Pure RC8 model-picker projection. The candidate list is Host-discovered
/// metadata; selected IDs outside that list cannot enter a settings mutation.
enum NativeDiscoveredModelSelection {
    static func initiallySelectedIDs(
        candidates: [LLMDiscoveredModelDTO],
        existingModels: [JSONValue]
    ) -> Set<String> {
        let known = Set(existingModels.compactMap(modelID))
        return Set(candidates.lazy.map(\.id).filter { !known.contains($0) })
    }

    static func adoptedModels(
        candidates: [LLMDiscoveredModelDTO],
        selectedIDs: Set<String>,
        existingModels: [JSONValue]
    ) -> [JSONValue] {
        var models = existingModels
        var known = Set(existingModels.compactMap(modelID))
        for candidate in candidates where selectedIDs.contains(candidate.id) {
            guard known.insert(candidate.id).inserted else { continue }
            models.append(modelValue(candidate))
        }
        return models
    }

    static func models(in namespace: SettingsNamespaceDTO, providerPath: [String]) -> [JSONValue] {
        var value = namespace.value
        for component in providerPath {
            guard let object = value.objectValue, let next = object[component] else { return [] }
            value = next
        }
        guard let object = value.objectValue, let models = object["models"]?.arrayValue else { return [] }
        return models
    }

    static func operation(
        candidates: [LLMDiscoveredModelDTO],
        selectedIDs: Set<String>,
        namespace: SettingsNamespaceDTO,
        providerPath: [String]
    ) -> SettingsPathOperationDTO? {
        let existing = models(in: namespace, providerPath: providerPath)
        let adopted = adoptedModels(candidates: candidates, selectedIDs: selectedIDs, existingModels: existing)
        guard adopted != existing else { return nil }
        return .set(path: providerPath + ["models"], value: .array(adopted))
    }

    private static func modelID(_ value: JSONValue) -> String? {
        value.objectValue?["id"]?.stringValue
    }

    private static func modelValue(_ candidate: LLMDiscoveredModelDTO) -> JSONValue {
        var value: [String: JSONValue] = ["id": .string(candidate.id)]
        if let name = candidate.name { value["name"] = .string(name) }
        if let contextWindow = candidate.contextWindow { value["contextWindow"] = .number(Double(contextWindow)) }
        if let maxTokens = candidate.maxTokens { value["maxTokens"] = .number(Double(maxTokens)) }
        return .object(value)
    }
}
