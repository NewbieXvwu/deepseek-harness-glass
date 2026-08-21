#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Read-only session stats derived exclusively from materialized assistant
/// nodes. Missing Host usage never becomes a locally estimated token count.
struct NativeStatsDockPresentation: Equatable {
    let turns: Int
    let steps: Int
    let inputTokens: Int?
    let outputTokens: Int?

    static func project(chatNodes: [ConversationViewNode]) -> Self? {
        let assistants = chatNodes.compactMap { $0.data as? CoreAssistantNode }
        guard !assistants.isEmpty else { return nil }
        let turns = Set(assistants.map(\.turn)).count
        let steps = Set(assistants.map { "\($0.turn):\($0.step)" }).count
        let usages = assistants.compactMap(\.usage)
        let input = tokenTotal(named: "inputTokens", usages: usages)
        let output = tokenTotal(named: "outputTokens", usages: usages)
        return .init(turns: turns, steps: steps, inputTokens: input, outputTokens: output)
    }

    private static func tokenTotal(named key: String, usages: [JSONValue]) -> Int? {
        let values = usages.compactMap { $0.objectValue?[key]?.numberValue }.map(Int.init)
        // A partial usage array does not represent a whole-session total.
        guard values.count == usages.count, !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}
