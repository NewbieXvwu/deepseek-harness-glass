#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Pure projection for the new-session preset seat. It deliberately has no
/// independent selection state: session composition and roster facts arrive
/// from the Host and determine whether a picker can be rendered.
enum NativeAgentPresetSeatPresentation {
    static func isAvailable(for session: SessionSummaryDTO?) -> Bool {
        session?.blank == true
    }

    static func options(from roster: [AgentPresetEntryDTO]) -> [AgentPresetEntryDTO] {
        roster.filter { $0.broken == nil }
    }

    static func currentID(session: SessionSummaryDTO, roster: [AgentPresetEntryDTO]) -> String? {
        let selectable = options(from: roster)
        if let configured = session.agentPreset,
           selectable.contains(where: { $0.id == configured }) {
            return configured
        }
        return selectable.first(where: { $0.isDefault })?.id ?? selectable.first?.id
    }
}
