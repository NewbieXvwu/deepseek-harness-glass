import SwiftUI

/// Auditable policy for every material-bearing native surface. The locked WebUI
/// remains the source of product hierarchy; this policy only decides whether
/// macOS may supply system chrome for an already-official affordance.
enum GlassPolicy: String, CaseIterable, Sendable {
    /// Official WebUI content, cards, rows, composer and dialogs retain their
    /// official tokens. Content must never receive incidental Liquid Glass.
    case content

    /// Navigation columns and titlebar belong to AppKit's system sidebar,
    /// inspector and toolbar APIs. SwiftUI must not add a second material.
    case systemNavigation

    /// A small official action that has no system navigation equivalent may use
    /// one regular glass treatment when it improves a pre-existing affordance.
    case regularGlassCustomControl

    /// Reserved for an official media overlay that needs translucent controls
    /// over live visual content. It is intentionally unused until such an
    /// official surface is implemented and reviewed.
    case clearGlassMediaOverlay

    var permitsCustomGlassEffect: Bool {
        switch self {
        case .regularGlassCustomControl, .clearGlassMediaOverlay:
            true
        case .content, .systemNavigation:
            false
        }
    }

    var ownsSystemNavigationMaterial: Bool {
        self == .systemNavigation
    }
}

/// Limits custom glass to the already-official floating action layer. System
/// sidebar, inspector and toolbar material is excluded because AppKit owns it.
enum GlassPolicyBudget {
    static let maximumCustomGlassControlsPerScene = 1

    static func permits(_ policies: [GlassPolicy]) -> Bool {
        policies.filter(\.permitsCustomGlassEffect).count <= maximumCustomGlassControlsPerScene
    }
}

extension View {
    /// The only permitted custom Liquid Glass entry point in GlassUI. Callsites
    /// must name their policy, while the implementation refuses to apply custom
    /// effects to WebUI content or system navigation material.
    @ViewBuilder
    func approvedGlassEffect<S: Shape>(_ policy: GlassPolicy, in shape: S) -> some View {
        switch policy {
        case .regularGlassCustomControl:
            glassEffect(.regular, in: shape)
        case .content, .systemNavigation, .clearGlassMediaOverlay:
            self
        }
    }
}
