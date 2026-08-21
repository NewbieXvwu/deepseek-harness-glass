#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// The native transcript may display only final assistant answer text. Typed
/// reasoning blocks remain reducer evidence and must never become Markdown,
/// clipboard payload, or accessibility content.
enum NativeAssistantTextPresentation {
    static func visibleText(_ assistant: CoreAssistantNode) -> String {
        assistant.blocks
            .filter { $0.kind == .text }
            .compactMap(\.text)
            .joined()
    }
}
