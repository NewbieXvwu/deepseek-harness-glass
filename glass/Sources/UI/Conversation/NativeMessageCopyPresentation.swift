#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Selects the stable Host identity that owns copy-feedback state. Text is
/// deliberately not an identity: multiple messages may have identical content,
/// while an assistant stream has no durable message until the Host publishes it.
enum NativeMessageCopyPresentation {
    static func hostMessageID(for node: ConversationViewNode) -> String? {
        if let user = node.data as? CoreUserMessageNode {
            guard user.kind != .context else { return nil }
            return user.messageID
        }
        if let assistant = node.data as? CoreAssistantNode {
            return assistant.messageID
        }
        return nil
    }

    static func hostMessageID(for assistant: CoreAssistantNode) -> String? {
        assistant.messageID
    }
}
