import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

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

    /// Only an implemented, reviewed control can request the scarce custom
    /// glass budget. The media-overlay case stays an explicit taxonomy value,
    /// but is reserved until its official surface and accessibility behavior are
    /// separately implemented and reviewed.
    var permitsCustomGlassEffect: Bool {
        self == .regularGlassCustomControl
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

/// Runtime decision used by actual SwiftUI materialization. Tests exercise this
/// production branch directly so policy enforcement does not depend on source
/// spelling or modifier syntax.
enum NativeGlassEffectDecision {
    static func materializes(policy: GlassPolicy, isEnabled: Bool) -> Bool {
        policy == .regularGlassCustomControl && isEnabled
    }
}

/// Keeps approved custom controls readable when macOS requests a less
/// translucent or higher-contrast appearance, and avoids fluid morphing when
/// motion is reduced. System navigation material remains outside this policy.
enum NativeGlassControlAccessibilityPolicy {
    static func permitsCustomGlass(
        reduceTransparency: Bool,
        contrast: ColorSchemeContrast
    ) -> Bool {
        !reduceTransparency && contrast == .standard
    }

    static func permitsMorphing(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

extension View {
    /// The only permitted custom Liquid Glass entry point in GlassUI. Callsites
    /// must name their policy, while the implementation refuses to apply custom
    /// effects to WebUI content or system navigation material.
    @ViewBuilder
    func approvedGlassEffect<S: Shape>(
        _ policy: GlassPolicy,
        in shape: S,
        isEnabled: Bool = true
    ) -> some View {
        if NativeGlassEffectDecision.materializes(policy: policy, isEnabled: isEnabled) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            self
        }
    }
}
