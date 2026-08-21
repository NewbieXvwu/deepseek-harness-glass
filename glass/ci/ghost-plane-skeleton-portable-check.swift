import Foundation

struct OfficialColumnLayout {
    let sidebar: CGFloat
    let center: CGFloat
    let details: CGFloat

    static func resolve(viewport: CGFloat, sidebarPreference: CGFloat, detailsPreference: CGFloat) -> Self {
        let sidebar = sidebarPreference == 0 ? 56 : sidebarPreference
        let details = detailsPreference == 0 ? 0 : detailsPreference
        return .init(sidebar: sidebar, center: max(0, viewport - sidebar - details), details: details)
    }
}

@main
struct GhostPlaneSkeletonPortableCheck {
    static func main() throws {
        let skeleton = try GhostPlaneSkeleton.build(.init(
            viewportWidth: 1280,
            sidebarPreference: 240,
            detailsPreference: 320,
            anchors: [
                .init(key: "message:1", kind: .user),
                .init(key: "call:tool-1", kind: .tool),
                .init(key: "turn:1", kind: .turnTail),
            ]
        ))
        guard skeleton.layout == .init(sidebarWidth: 240, centerWidth: 720, detailsWidth: 320) else {
            throw CheckFailure("skeleton must use supplied official column resolution")
        }
        let requiredFragments = [
            "data-conversation-scroll=\"\"",
            "data-chat-flow=\"\"",
            "data-chat-anchor-key=\"message:1\"",
            "data-chat-flow-key=\"message:1\"",
            "data-streaming=\"false\"",
            "data-composer-seat=\"\"",
            "data-slot=\"conversation.session\"",
            "data-slot=\"conversation.session.header\"",
            "data-slot=\"conversation.chat.node\"",
            "data-slot=\"conversation.chat.turnTail\"",
            "data-slot=\"conversation.details.tool\"",
            "data-slot=\"conversation.composer\"",
            "data-slot=\"tool.call.toolview\"",
        ]
        guard requiredFragments.allSatisfy(skeleton.html.contains) else {
            throw CheckFailure("skeleton omitted one or more required official slot/anchor contracts")
        }
        guard GhostPlaneSkeleton.requiredSelectors.count == requiredFragments.count else {
            throw CheckFailure("selector inventory and generated skeleton assertion set diverged")
        }
        guard skeleton.html.contains("data-chat-anchor-key=\"message:1\""),
              skeleton.html.contains("data-chat-flow-kind=\"tool\""),
              skeleton.html.contains("data-streaming=\"false\""),
              !skeleton.html.contains("user authored content") else {
            throw CheckFailure("skeleton must retain anchors without content")
        }
        do {
            _ = try GhostPlaneSkeleton.build(.init(
                viewportWidth: 800, sidebarPreference: 0, detailsPreference: 0,
                anchors: [.init(key: "<script>", kind: .assistant)]
            ))
            throw CheckFailure("unsafe anchor must be rejected before HTML generation")
        } catch GhostPlaneSkeleton.Error.invalidAnchorKey {
            // expected
        }
        print("ghost plane skeleton portable check passed")
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
