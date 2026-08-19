import AppKit
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// Official SVG assets are rendered from the bundle rather than substituted by
/// SF Symbols. Their provenance is registered in `official-ui-catalog.json`.
struct OfficialAssetImage: View {
    let name: String
    var template = false

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: configured(image))
                    .resizable()
                    .renderingMode(template ? .template : .original)
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }

    private func configured(_ image: NSImage) -> NSImage {
        image.isTemplate = template
        return image
    }
}

struct OfficialCircleIconButtonStyle: ButtonStyle {
    let pressedForeground: Color

    init(pressedForeground: Color = OfficialUISpec.Token.secondary) {
        self.pressedForeground = pressedForeground
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(pressedForeground)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: Circle()
            )
    }
}

struct OfficialNewSessionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.primary)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.interactiveHover : OfficialUISpec.Token.elevated,
                in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous)
                    .stroke(OfficialUISpec.Token.border, lineWidth: 1)
            }
    }
}

struct OfficialSidebarRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.secondary)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
            )
    }
}

struct OfficialComposerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.secondary)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.interactiveHover : Color.clear,
                in: Circle()
            )
    }
}

/// Liquid Glass is reserved for the window-navigation affordance. It never
/// covers an official WebUI content surface, list row, or composer body.
struct NativeGlassNavigationButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let permitsCustomGlass = NativeGlassControlAccessibilityPolicy.permitsCustomGlass(
            reduceTransparency: reduceTransparency,
            contrast: contrast
        )
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.primary)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(OfficialUISpec.Token.primaryForeground.opacity(0.72), lineWidth: 0.8)
            }
            .approvedGlassEffect(
                .regularGlassCustomControl,
                in: Circle(),
                isEnabled: permitsCustomGlass
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// Exact two-layer projection of `--dsw-shadow-lv2` from the locked official
/// `gradient-shadow-text.css`. `radius` is CSS blur / 2 under SwiftUI's shadow API.
extension View {
    func officialLevel2Shadow() -> some View {
        shadow(
            color: OfficialUISpec.Shadow.level2OuterColor,
            radius: OfficialUISpec.Shadow.level2OuterRadius,
            y: OfficialUISpec.Shadow.level2OuterY
        )
        .shadow(
            color: OfficialUISpec.Shadow.level2InnerColor,
            radius: OfficialUISpec.Shadow.level2InnerRadius,
            y: OfficialUISpec.Shadow.level2InnerY
        )
    }
}
