import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native RC8 `conversation.input.access` seat. The complete session-level
/// `permissions` projection remains Host authority; changing a preset delegates
/// only to the Store's `/permission <preset>` command seam and waits for the
/// next projection push to update visible state.
@MainActor
struct NativeComposerPermissionSelector: View {
    @ObservedObject var sessionStore: NativeSessionStore

    @State private var pendingFullAccess = false
    @State private var acknowledgedFullAccess = false

    private var permission: CoreSessionPermissionSelect? { sessionStore.extensionState?.permissions }
    private var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    private var currentOption: CoreSessionPermissionSelect.Option? {
        guard let permission else { return nil }
        return permission.options.first(where: { $0.value == permission.currentValue })
    }

    private var currentName: String {
        currentOption.map(displayName) ?? ""
    }

    private var triggerAccessibilityLabel: String {
        t("input.accessMode", replacements: ["name": currentName])
    }

    var body: some View {
        if let permission {
            Menu {
                ForEach(permission.options.filter { $0.value != "custom" }) { option in
                    let selected = option.value == permission.currentValue
                    Button {
                        choose(option)
                    } label: {
                        HStack(spacing: OfficialUISpec.Spacing.p8) {
                            permissionGlyph(for: option.value)
                            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                                Text(displayName(option))
                                    .font(OfficialUISpec.Typography.sStrong14)
                                if let description = option.description {
                                    Text(description)
                                        .font(OfficialUISpec.Typography.xxs12)
                                        .foregroundStyle(OfficialUISpec.Token.caption)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: OfficialUISpec.Spacing.p0)
                            if selected {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .disabled(selected || sessionStore.isSubmittingPermission)
                    .accessibilityLabel(displayName(option))
                    .accessibilityValue(selected ? triggerAccessibilityLabel : "")
                }
            } label: {
                HStack(spacing: OfficialUISpec.Spacing.p2) {
                    permissionGlyph(for: permission.currentValue)
                    Text(currentName)
                        .lineLimit(1)
                    OfficialAssetImage(name: "icon-chevron-down", template: true)
                        .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    if sessionStore.isSubmittingPermission {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .frame(minHeight: OfficialUISpec.Layout.composerControlHeight, alignment: .leading)
                .padding(.trailing, OfficialUISpec.Spacing.p12)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(triggerAccessibilityLabel)
            .popover(isPresented: $pendingFullAccess, arrowEdge: .bottom) {
                fullAccessConfirmation
            }
        }
    }

    private func choose(_ option: CoreSessionPermissionSelect.Option) {
        guard option.value != permission?.currentValue else { return }
        if option.value == PermissionPresetProjection.fullAccessPreset {
            acknowledgedFullAccess = false
            pendingFullAccess = true
        } else {
            sessionStore.selectPermissionPreset(option.value)
        }
    }

    private func displayName(_ option: CoreSessionPermissionSelect.Option) -> String {
        if option.value == PermissionPresetProjection.fullAccessPreset {
            return OfficialUISpec.Text.permissionFullAccess
        }
        return PermissionPresetProjection.display(value: option.value, suppliedLabel: option.name)
    }

    @ViewBuilder
    private func permissionGlyph(for value: String) -> some View {
        if value == "workspace-write" {
            OfficialAssetImage(name: "icon-permission-workspace-write", template: true)
                .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .accessibilityHidden(true)
        }
    }

    private var fullAccessConfirmation: some View {
        NativeFullAccessPermissionConfirmation(
            acknowledged: $acknowledgedFullAccess,
            submitting: sessionStore.isSubmittingPermission,
            language: language,
            cancel: {
                pendingFullAccess = false
                acknowledgedFullAccess = false
            },
            enable: {
                pendingFullAccess = false
                sessionStore.selectPermissionPreset(PermissionPresetProjection.fullAccessPreset)
            }
        )
    }

    /// Product text remains in the locked RC8 `ui-conversation` locale catalog.
    private func t(_ key: String, replacements: [String: String] = [:]) -> String {
        Self.localizedValue(key: key, language: language, replacements: replacements)
    }

    static func localizedValue(
        key: String,
        language: String,
        replacements: [String: String] = [:]
    ) -> String {
        var value = OfficialUISpec.LocaleCatalog.value(
            namespace: "ui-conversation",
            key: key,
            language: language
        ) ?? key
        for (token, replacement) in replacements {
            value = value.replacingOccurrences(of: "{\(token)}", with: replacement)
        }
        return value
    }
}

/// Native RC8 confirmation content for the `danger-full-access` access preset.
/// It is separate from the selector menu only to permit direct macOS AX testing;
/// the owning selector still presents this exact view in its native popover.
@MainActor
struct NativeFullAccessPermissionConfirmation: View {
    @Binding var acknowledged: Bool
    let submitting: Bool
    let language: String
    let cancel: () -> Void
    let enable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p12) {
            Text(t("access.confirm.title"))
                .font(OfficialUISpec.Typography.baseStrong16)
            Text(t("access.confirm.description"))
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(t("access.confirm.acknowledge"), isOn: $acknowledged)
                .font(OfficialUISpec.Typography.s14)
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Button(t("access.confirm.cancel"), action: cancel)
                    .buttonStyle(.bordered)
                Spacer(minLength: OfficialUISpec.Spacing.p0)
                Button(t("access.confirm.enable"), action: enable)
                    .buttonStyle(.borderedProminent)
                    .disabled(!acknowledged || submitting)
            }
        }
        .padding(OfficialUISpec.Spacing.p16)
        .frame(width: OfficialUISpec.Geometry.px320)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("access.confirm.title"))
    }

    private func t(_ key: String) -> String {
        NativeComposerPermissionSelector.localizedValue(key: key, language: language)
    }
}
