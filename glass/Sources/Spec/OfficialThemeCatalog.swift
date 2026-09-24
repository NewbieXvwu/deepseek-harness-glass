import AppKit
import Foundation
import SwiftUI

struct OfficialRGBA: Hashable, Sendable, Decodable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    func color(for scheme: ColorScheme) -> Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct OfficialColorToken: Hashable, Sendable {
    let cssName: String
    let light: OfficialRGBA
    let dark: OfficialRGBA

    func color(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? dark : light).color(for: scheme)
    }

    var lightColor: Color { light.color(for: .light) }
    var darkColor: Color { dark.color(for: .dark) }

    var adaptiveColor: Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        })
    }
}

extension OfficialUISpec {
    enum Theme {
        private struct Document: Decodable {
            let schemaVersion: Int
            let tokens: [Token]
        }

        private struct Token: Decodable {
            let cssName: String
            let light: Variant
            let dark: Variant
        }

        private struct Variant: Decodable {
            let resolvedRGBA: OfficialRGBA
        }

        static let colorTokens: [String: OfficialColorToken] = {
            guard let url = resourceBundle.url(forResource: "official-theme-tokens", withExtension: "json") else {
                fatalError("official-theme-tokens.json is missing from GlassSpec resources")
            }
            do {
                let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
                guard document.schemaVersion == 1 else {
                    fatalError("unsupported official theme schema \(document.schemaVersion)")
                }
                let pairs = document.tokens.map { token in
                    (token.cssName, OfficialColorToken(
                        cssName: token.cssName,
                        light: token.light.resolvedRGBA,
                        dark: token.dark.resolvedRGBA
                    ))
                }
                guard Set(pairs.map(\.0)).count == pairs.count else {
                    fatalError("official theme catalog contains duplicate CSS token names")
                }
                return Dictionary(uniqueKeysWithValues: pairs)
            } catch {
                fatalError("official theme catalog is invalid: \(error)")
            }
        }()

        static func value(_ cssName: String) -> OfficialColorToken {
            guard let token = colorTokens[cssName] else {
                preconditionFailure("Unknown official color token: \(cssName)")
            }
            return token
        }

        private static var resourceBundle: Bundle {
#if SWIFT_PACKAGE
            .module
#else
            .main
#endif
        }

        static let aliasBgBase = value("--dsw-alias-bg-base")
        static let aliasBgLayer1 = value("--dsw-alias-bg-layer-1")
        static let aliasBgLayer2 = value("--dsw-alias-bg-layer-2")
        static let aliasBgLayer3 = value("--dsw-alias-bg-layer-3")
        static let aliasBgMask1 = value("--dsw-alias-bg-mask-1")
        static let aliasBgMask2 = value("--dsw-alias-bg-mask-2")
        static let aliasBgMask3 = value("--dsw-alias-bg-mask-3")
        static let aliasBgMaskDrop = value("--dsw-alias-bg-mask-drop")
        static let aliasBgMaskPhoto = value("--dsw-alias-bg-mask-photo")
        static let aliasBgModulePlatform = value("--dsw-alias-bg-module-platform")
        static let aliasBgMultiSelect = value("--dsw-alias-bg-multi-select")
        static let aliasBgOverlay = value("--dsw-alias-bg-overlay")
        static let aliasBgSkeleton = value("--dsw-alias-bg-skeleton")
        static let aliasBorderInverted = value("--dsw-alias-border-inverted")
        static let aliasBorderInverted2 = value("--dsw-alias-border-inverted2")
        static let aliasBorderL1 = value("--dsw-alias-border-l1")
        static let aliasBorderL2 = value("--dsw-alias-border-l2")
        static let aliasBorderL2DarkmodeThin = value("--dsw-alias-border-l2-darkmode-thin")
        static let aliasBorderL3 = value("--dsw-alias-border-l3")
        static let aliasBorderL4 = value("--dsw-alias-border-l4")
        static let aliasBrandPrimary = value("--dsw-alias-brand-primary")
        static let aliasBrandPrimaryInvert = value("--dsw-alias-brand-primary-invert")
        static let aliasBrandPrimaryNewColorprimaryNewColor = value("--dsw-alias-brand-primary-new-colorprimary-new-color")
        static let aliasBrandText = value("--dsw-alias-brand-text")
        static let aliasButtonContrastFill = value("--dsw-alias-button-contrast-fill")
        static let aliasButtonElevatedFill = value("--dsw-alias-button-elevated-fill")
        static let aliasButtonFloatingFill = value("--dsw-alias-button-floating-fill")
        static let aliasButtonFloatingHover = value("--dsw-alias-button-floating-hover")
        static let aliasButtonGhostActiveBorder = value("--dsw-alias-button-ghost-active-border")
        static let aliasButtonGhostActiveFill = value("--dsw-alias-button-ghost-active-fill")
        static let aliasButtonGhostActiveHover = value("--dsw-alias-button-ghost-active-hover")
        static let aliasButtonInfoFill = value("--dsw-alias-button-info-fill")
        static let aliasButtonInfoHover = value("--dsw-alias-button-info-hover")
        static let aliasButtonPrimaryDimmed = value("--dsw-alias-button-primary-dimmed")
        static let aliasButtonPrimaryFill = value("--dsw-alias-button-primary-fill")
        static let aliasButtonPrimaryHover = value("--dsw-alias-button-primary-hover")
        static let aliasButtonToolBarFill = value("--dsw-alias-button-tool-bar-fill")
        static let aliasButtonToolBarFillInvisible = value("--dsw-alias-button-tool-bar-fill-invisible")
        static let aliasButtonToolBarHover = value("--dsw-alias-button-tool-bar-hover")
        static let aliasInteractiveBgActive = value("--dsw-alias-interactive-bg-active")
        static let aliasInteractiveBgHover = value("--dsw-alias-interactive-bg-hover")
        static let aliasInteractiveBgHoverAccent = value("--dsw-alias-interactive-bg-hover-accent")
        static let aliasInteractiveBgHoverDanger = value("--dsw-alias-interactive-bg-hover-danger")
        static let aliasInteractiveBgHoverSolid = value("--dsw-alias-interactive-bg-hover-solid")
        static let aliasLabelCaption = value("--dsw-alias-label-caption")
        static let aliasLabelDimmed = value("--dsw-alias-label-dimmed")
        static let aliasLabelPrimary = value("--dsw-alias-label-primary")
        static let aliasLabelPrimaryBluish = value("--dsw-alias-label-primary-bluish")
        static let aliasLabelPrimaryDimmed = value("--dsw-alias-label-primary-dimmed")
        static let aliasLabelPrimaryForeground = value("--dsw-alias-label-primary-foreground")
        static let aliasLabelPrimaryInverted = value("--dsw-alias-label-primary-inverted")
        static let aliasLabelSecondary = value("--dsw-alias-label-secondary")
        static let aliasLabelTertiary = value("--dsw-alias-label-tertiary")
        static let aliasMarkdownCitation = value("--dsw-alias-markdown-citation")
        static let aliasMarkdownCodeBlock = value("--dsw-alias-markdown-code-block")
        static let aliasMarkdownCodeBlockBanner = value("--dsw-alias-markdown-code-block-banner")
        static let aliasMarkdownCodeSegmentSelected = value("--dsw-alias-markdown-code-segment-selected")
        static let aliasMarkdownCodeSegmentUnselected = value("--dsw-alias-markdown-code-segment-unselected")
        static let aliasMarkdownInlineCode = value("--dsw-alias-markdown-inline-code")
        static let aliasMarkdownPlaceholder = value("--dsw-alias-markdown-placeholder")
        static let aliasMarkdownTag = value("--dsw-alias-markdown-tag")
        static let aliasScrollbarBgL1 = value("--dsw-alias-scrollbar-bg-l1")
        static let aliasScrollbarBgL2 = value("--dsw-alias-scrollbar-bg-l2")
        static let aliasScrollbarHoverL1 = value("--dsw-alias-scrollbar-hover-l1")
        static let aliasScrollbarHoverL2 = value("--dsw-alias-scrollbar-hover-l2")
        static let aliasStateBusinessPrimary = value("--dsw-alias-state-business-primary")
        static let aliasStateBusinessTertiary = value("--dsw-alias-state-business-tertiary")
        static let aliasStateErrorPrimary = value("--dsw-alias-state-error-primary")
        static let aliasStateErrorSecondary = value("--dsw-alias-state-error-secondary")
        static let aliasStateSuccessPrimary = value("--dsw-alias-state-success-primary")
        static let aliasStateSuccessSecondary = value("--dsw-alias-state-success-secondary")
        static let aliasStateSuccessTertiary = value("--dsw-alias-state-success-tertiary")
        static let aliasStateWarnLabel = value("--dsw-alias-state-warn-label")
        static let aliasStateWarnPrimary = value("--dsw-alias-state-warn-primary")
        static let aliasStateWarnSecondary = value("--dsw-alias-state-warn-secondary")
        static let aliasStateWarnTertiary = value("--dsw-alias-state-warn-tertiary")
        static let aliasToastBg = value("--dsw-alias-toast-bg")
        static let aliasTooltipBg = value("--dsw-alias-tooltip-bg")
        static let specificBubble = value("--dsw-specific-bubble")
        static let specificBubbleHighlight = value("--dsw-specific-bubble-highlight")
        static let specificInputMajor = value("--dsw-specific-input-major")
        static let specificLoginInput = value("--dsw-specific-login-input")
        static let specificMenu = value("--dsw-specific-menu")
        static let specificSelector = value("--dsw-specific-selector")
        static let specificSidebarFill = value("--dsw-specific-sidebar-fill")
        static let specificSidebarNavItemActive = value("--dsw-specific-sidebar-nav-item-active")
        static let specificSidebarNavItemActiveAccent = value("--dsw-specific-sidebar-nav-item-active-accent")
        static let specificSidebarNavItemHover = value("--dsw-specific-sidebar-nav-item-hover")
        static let specificTip = value("--dsw-specific-tip")
        static let staticAmber100 = value("--dsw-static-amber-100")
        static let staticAmber400 = value("--dsw-static-amber-400")
        static let staticAmber500 = value("--dsw-static-amber-500")
        static let staticAmber600 = value("--dsw-static-amber-600")
        static let staticAmber900 = value("--dsw-static-amber-900")
        static let staticBlue100 = value("--dsw-static-blue-100")
        static let staticBlue300 = value("--dsw-static-blue-300")
        static let staticBlue400 = value("--dsw-static-blue-400")
        static let staticBlue450 = value("--dsw-static-blue-450")
        static let staticBlue50 = value("--dsw-static-blue-50")
        static let staticBlue500 = value("--dsw-static-blue-500")
        static let staticBlue50p = value("--dsw-static-blue-50p")
        static let staticBlue600 = value("--dsw-static-blue-600")
        static let staticBlue75 = value("--dsw-static-blue-75")
        static let staticBlue800 = value("--dsw-static-blue-800")
        static let staticBlue900 = value("--dsw-static-blue-900")
        static let staticBlue950 = value("--dsw-static-blue-950")
        static let staticDeepseek100 = value("--dsw-static-deepseek-100")
        static let staticDeepseek200 = value("--dsw-static-deepseek-200")
        static let staticDeepseek300 = value("--dsw-static-deepseek-300")
        static let staticDeepseek400 = value("--dsw-static-deepseek-400")
        static let staticDeepseek450 = value("--dsw-static-deepseek-450")
        static let staticDeepseek50 = value("--dsw-static-deepseek-50")
        static let staticDeepseek500 = value("--dsw-static-deepseek-500")
        static let staticDeepseek600 = value("--dsw-static-deepseek-600")
        static let staticDeepseek700Delete = value("--dsw-static-deepseek-700-delete")
        static let staticDeepseek800 = value("--dsw-static-deepseek-800")
        static let staticDeepseek900 = value("--dsw-static-deepseek-900")
        static let staticGreen100 = value("--dsw-static-green-100")
        static let staticGreen400 = value("--dsw-static-green-400")
        static let staticGreen500 = value("--dsw-static-green-500")
        static let staticGreen900 = value("--dsw-static-green-900")
        static let staticNeutral00 = value("--dsw-static-neutral-00")
        static let staticNeutral100 = value("--dsw-static-neutral-100")
        static let staticNeutral1000 = value("--dsw-static-neutral-1000")
        static let staticNeutral150 = value("--dsw-static-neutral-150")
        static let staticNeutral200 = value("--dsw-static-neutral-200")
        static let staticNeutral250 = value("--dsw-static-neutral-250")
        static let staticNeutral300 = value("--dsw-static-neutral-300")
        static let staticNeutral400 = value("--dsw-static-neutral-400")
        static let staticNeutral50 = value("--dsw-static-neutral-50")
        static let staticNeutral500 = value("--dsw-static-neutral-500")
        static let staticNeutral550 = value("--dsw-static-neutral-550")
        static let staticNeutral600 = value("--dsw-static-neutral-600")
        static let staticNeutral700 = value("--dsw-static-neutral-700")
        static let staticNeutral800 = value("--dsw-static-neutral-800")
        static let staticNeutral850 = value("--dsw-static-neutral-850")
        static let staticNeutral900 = value("--dsw-static-neutral-900")
        static let staticNeutralBluish00 = value("--dsw-static-neutral-bluish-00")
        static let staticNeutralBluish100 = value("--dsw-static-neutral-bluish-100")
        static let staticNeutralBluish1000 = value("--dsw-static-neutral-bluish-1000")
        static let staticNeutralBluish150 = value("--dsw-static-neutral-bluish-150")
        static let staticNeutralBluish200 = value("--dsw-static-neutral-bluish-200")
        static let staticNeutralBluish300 = value("--dsw-static-neutral-bluish-300")
        static let staticNeutralBluish400 = value("--dsw-static-neutral-bluish-400")
        static let staticNeutralBluish50 = value("--dsw-static-neutral-bluish-50")
        static let staticNeutralBluish500 = value("--dsw-static-neutral-bluish-500")
        static let staticNeutralBluish60 = value("--dsw-static-neutral-bluish-60")
        static let staticNeutralBluish600 = value("--dsw-static-neutral-bluish-600")
        static let staticNeutralBluish700 = value("--dsw-static-neutral-bluish-700")
        static let staticNeutralBluish75 = value("--dsw-static-neutral-bluish-75")
        static let staticNeutralBluish750 = value("--dsw-static-neutral-bluish-750")
        static let staticNeutralBluish800 = value("--dsw-static-neutral-bluish-800")
        static let staticNeutralBluish850 = value("--dsw-static-neutral-bluish-850")
        static let staticNeutralBluish875 = value("--dsw-static-neutral-bluish-875")
        static let staticNeutralBluish900 = value("--dsw-static-neutral-bluish-900")
        static let staticNeutralBluish950 = value("--dsw-static-neutral-bluish-950")
        static let staticRed100 = value("--dsw-static-red-100")
        static let staticRed400 = value("--dsw-static-red-400")
        static let staticRed50 = value("--dsw-static-red-50")
        static let staticRed500 = value("--dsw-static-red-500")
        static let staticRed600 = value("--dsw-static-red-600")
        static let staticRed900 = value("--dsw-static-red-900")
    }
}
