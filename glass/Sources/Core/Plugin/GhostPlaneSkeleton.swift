import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Native-authoritative input for the Ghost Plane's empty structural document.
/// It contains only geometry and stable Host/node identity; user content and
/// plugin code are deliberately absent from the generated HTML.
struct GhostPlaneSkeletonInput: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case settling
        case hero
        case active
    }

    struct ChatAnchor: Equatable, Sendable, Identifiable {
        enum Kind: String, Equatable, Sendable {
            case user
            case assistant
            case tool
            case turnTail
        }

        let key: String
        let kind: Kind

        var id: String { key }
    }

    let viewportWidth: Double
    let sidebarPreference: Double
    let detailsPreference: Double
    let phase: Phase
    let anchors: [ChatAnchor]

    init(
        viewportWidth: Double,
        sidebarPreference: Double,
        detailsPreference: Double,
        phase: Phase = .active,
        anchors: [ChatAnchor]
    ) {
        self.viewportWidth = viewportWidth
        self.sidebarPreference = sidebarPreference
        self.detailsPreference = detailsPreference
        self.phase = phase
        self.anchors = anchors
    }
}

struct GhostPlaneSkeleton: Equatable, Sendable {
    struct Layout: Equatable, Sendable {
        let sidebarWidth: Double
        let centerWidth: Double
        let detailsWidth: Double
    }

    struct ElementMap: Equatable, Sendable {
        let rootID: String
        let sessionHeaderID: String
        let conversationScrollID: String
        let scrollContentID: String
        let chatFlowID: String
        let composerSeatID: String
        let turnTailID: String
        let toolviewID: String
        let detailsToolID: String
        let anchorElementIDs: [String: String]
    }

    /// Contract inventory consumed by future T11.8 drift checks. Each selector
    /// comes from the official ConversationRoot/ChatView/SlotMap contracts, not
    /// an inferred screenshot shape.
    static let requiredSelectors = [
        "[data-conversation-scroll]",
        "[data-chat-flow]",
        "[data-chat-anchor-key]",
        "[data-chat-flow-key]",
        "[data-chat-flow-kind]",
        "[data-streaming]",
        "[data-phase]",
        "[data-composer-seat]",
        "[data-slot=conversation.session]",
        "[data-slot=conversation.session.header]",
        "[data-slot=conversation.chat.node]",
        "[data-slot=conversation.chat.turnTail]",
        "[data-slot=conversation.details.tool]",
        "[data-slot=conversation.composer]",
        "[data-slot=tool.call.toolview]",
    ]

    let html: String
    let layout: Layout
    let elements: ElementMap

    static func build(_ input: GhostPlaneSkeletonInput) throws -> Self {
        guard input.viewportWidth.isFinite, input.viewportWidth >= 0,
              input.sidebarPreference.isFinite, input.detailsPreference.isFinite
        else { throw Error.invalidGeometry }
        guard Set(input.anchors.map(\.key)).count == input.anchors.count else {
            throw Error.duplicateAnchorKey
        }
        guard input.anchors.allSatisfy({ validAnchorKey($0.key) }) else {
            throw Error.invalidAnchorKey
        }

        let resolved = OfficialColumnLayout.resolve(
            viewport: CGFloat(input.viewportWidth),
            sidebarPreference: CGFloat(input.sidebarPreference),
            detailsPreference: CGFloat(input.detailsPreference)
        )
        let layout = Layout(
            sidebarWidth: Double(resolved.sidebar),
            centerWidth: Double(resolved.center),
            detailsWidth: Double(resolved.details)
        )
        let anchorElementIDs = Dictionary(uniqueKeysWithValues: input.anchors.map {
            ($0.key, "ghost-chat-anchor-\(elementSuffix($0.key))")
        })
        let elements = ElementMap(
            rootID: "ghost-plane-root",
            sessionHeaderID: "ghost-session-header",
            conversationScrollID: "ghost-conversation-scroll",
            scrollContentID: "ghost-scroll-content",
            chatFlowID: "ghost-chat-flow",
            composerSeatID: "ghost-composer-seat",
            turnTailID: "ghost-turn-tail",
            toolviewID: "ghost-toolview",
            detailsToolID: "ghost-details-tool",
            anchorElementIDs: anchorElementIDs
        )
        let rows = input.anchors.map { anchor in
            let id = anchorElementIDs[anchor.key]!
            return "<div id=\"\(id)\" data-chat-anchor-key=\"\(escape(anchor.key))\" data-chat-flow-key=\"\(escape(anchor.key))\" data-chat-flow-kind=\"\(anchor.kind.rawValue)\" data-slot=\"conversation.chat.node\" data-streaming=\"false\"></div>"
        }.joined(separator: "\n")
        let html = """
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body>
          <div id="\(elements.rootID)" data-ghost-plane="skeleton" data-phase="\(input.phase.rawValue)" style="display:grid;grid-template-columns:\(cssPixels(layout.sidebarWidth)) \(cssPixels(layout.centerWidth)) \(cssPixels(layout.detailsWidth));">
            <aside id="ghost-sidebar" data-ghost-zone="sidebar"></aside>
            <main id="ghost-conversation" data-ghost-zone="conversation">
              <header id="\(elements.sessionHeaderID)" data-slot="conversation.session.header"></header>
              <div id="\(elements.conversationScrollID)" data-conversation-scroll="">
                <div id="\(elements.scrollContentID)" data-ghost-scroll-content="">
                  <section id="ghost-session" data-slot="conversation.session">
                    <div id="\(elements.chatFlowID)" data-chat-flow="">
                      \(rows)
                      <div id="\(elements.turnTailID)" data-slot="conversation.chat.turnTail"></div>
                      <div id="\(elements.toolviewID)" data-slot="tool.call.toolview"></div>
                    </div>
                  </section>
                  <div id="\(elements.composerSeatID)" data-composer-seat="" data-slot="conversation.composer"></div>
                </div>
              </div>
            </main>
            <aside id="ghost-details" data-ghost-zone="details">
              <div id="\(elements.detailsToolID)" data-slot="conversation.details.tool"></div>
            </aside>
          </div>
        </body>
        </html>
        """
        return Self(html: html, layout: layout, elements: elements)
    }

    enum Error: Swift.Error, Equatable, Sendable {
        case invalidGeometry
        case duplicateAnchorKey
        case invalidAnchorKey
    }

    private static func validAnchorKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 256 else { return false }
        return key.unicodeScalars.allSatisfy(validAnchorScalar)
    }

    private static func elementSuffix(_ key: String) -> String {
        var result = String()
        result.reserveCapacity(key.count)
        for scalar in key.unicodeScalars {
            result.append(validAnchorScalar(scalar) ? Character(scalar) : "-")
        }
        return result
    }

    private static func validAnchorScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 46, 58, 95, 48...57, 65...90, 97...122: true // - . : _ ASCII alphanumerics
        default: false
        }
    }

    private static func escape(_ value: String) -> String {
        var result = String()
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result.append("&amp;")
            case "\"": result.append("&quot;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func cssPixels(_ value: Double) -> String {
        "\(Int(value.rounded()))px"
    }
}
