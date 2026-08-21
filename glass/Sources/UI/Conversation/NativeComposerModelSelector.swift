import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native RC8 `conversation.input.model` seat. The complete model directory and
/// the selected route remain Host authority; this view only renders advertised
/// choices and delegates mutations to `NativeSessionStore.selectModel`.
@MainActor
struct NativeComposerModelSelector: View {
    @ObservedObject var sessionStore: NativeSessionStore

    private var directory: CoreSessionModelDirectory? { sessionStore.modelDirectory }
    private var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    private var currentModel: CoreSessionModelDirectory.Model? {
        guard let directory else { return nil }
        return directory.groups
            .first(where: { $0.id == directory.current.provider })?
            .models
            .first(where: { $0.id == directory.current.model })
    }

    private var currentModelName: String {
        currentModel?.name ?? t("trigger.fallback")
    }

    private var effectiveEffortID: String? {
        guard let directory else { return nil }
        return directory.current.reasoningEffort ?? currentModel?.defaultReasoningEffort
    }

    private var currentEffortName: String? {
        guard let currentModel else { return nil }
        guard let effortID = effectiveEffortID else {
            return currentModel.defaultReasoningEffort == nil ? t("effort.providerDefault") : nil
        }
        return currentModel.reasoningEfforts.first(where: { $0.id == effortID })?.name ?? effortID
    }

    private var triggerAccessibilityLabel: String {
        guard let directory, directory.contains(provider: directory.current.provider, model: directory.current.model) else {
            return t("trigger.selectAria")
        }
        if let currentEffortName {
            return t("trigger.ariaEffort", replacements: ["model": currentModelName, "effort": currentEffortName])
        }
        return t("trigger.aria", replacements: ["model": currentModelName])
    }

    var body: some View {
        if let directory, directory.routable {
            Menu {
                modelStatusRows
                Menu {
                    modelChoices(directory)
                } label: {
                    rootCell(label: t("menu.model"), value: currentModelName)
                }

                if currentModel != nil {
                    Menu {
                        effortChoices(directory)
                    } label: {
                        rootCell(label: t("menu.effort"), value: currentEffortName ?? t("effort.providerDefault"))
                    }
                }
            } label: {
                triggerLabel
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(triggerAccessibilityLabel)
            .accessibilityHint(t("menu.aria"))
        } else if sessionStore.modelDirectoryStatus != .idle {
            Menu {
                modelStatusRows
            } label: {
                triggerLabel
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(triggerAccessibilityLabel)
            .accessibilityHint(t("menu.aria"))
        }
    }

    private var triggerLabel: some View {
        HStack(spacing: OfficialUISpec.Spacing.p2) {
            Text(currentModelName)
                .lineLimit(1)
            if let currentEffortName {
                Text(currentEffortName)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .lineLimit(1)
            }
            OfficialAssetImage(name: "icon-chevron-down", template: true)
                .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                .foregroundStyle(OfficialUISpec.Token.caption)
            if sessionStore.modelDirectoryStatus == .loading || sessionStore.isSelectingModel {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .font(OfficialUISpec.Typography.xsStrong13)
        .foregroundStyle(OfficialUISpec.Token.primary)
        .frame(minHeight: OfficialUISpec.Layout.composerControlHeight, alignment: .leading)
        .padding(.trailing, OfficialUISpec.Spacing.p12)
    }

    @ViewBuilder
    private var modelStatusRows: some View {
        switch sessionStore.modelDirectoryStatus {
        case .loading:
            Text(t("status.loading"))
        case let .error(message):
            Text(t("error.action", replacements: ["message": message]))
                .foregroundStyle(OfficialUISpec.Token.errorPrimary)
            Button(t("action.reload")) {
                sessionStore.reloadModelDirectory()
            }
        case .idle, .ready, .selecting:
            EmptyView()
        }
    }

    @ViewBuilder
    private func modelChoices(_ directory: CoreSessionModelDirectory) -> some View {
        if directory.groups.isEmpty {
            Text(t("empty.models"))
        } else {
            ForEach(directory.failures) { failure in
                Text(t("warning.groupLoad", replacements: ["name": failure.name, "message": failure.message]))
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
            }
            ForEach(directory.groups) { group in
                Section(group.name) {
                    ForEach(group.models) { model in
                        let selected = directory.current.provider == group.id && directory.current.model == model.id
                        Button {
                            guard !selected else { return }
                            sessionStore.selectModel(
                                provider: group.id,
                                model: model.id,
                                reasoningEffort: model.defaultReasoningEffort
                            )
                        } label: {
                            HStack(spacing: OfficialUISpec.Spacing.p8) {
                                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                                    Text(model.name)
                                        .font(OfficialUISpec.Typography.sStrong14)
                                    if let description = model.description {
                                        Text(description)
                                            .font(OfficialUISpec.Typography.xxs12)
                                            .foregroundStyle(OfficialUISpec.Token.caption)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: OfficialUISpec.Spacing.p0)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .disabled(sessionStore.isSelectingModel)
                        .accessibilityLabel(model.name)
                        .accessibilityValue(selected ? t("menu.model") : "")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func effortChoices(_ directory: CoreSessionModelDirectory) -> some View {
        if let currentModel {
            let options = effortOptions(for: currentModel)
            if options.isEmpty {
                Text(t("empty.efforts"))
            } else {
                ForEach(options) { option in
                    let selected = effectiveEffortID == option.id
                    Button {
                        guard !selected else { return }
                        sessionStore.selectModel(
                            provider: directory.current.provider,
                            model: directory.current.model,
                            reasoningEffort: option.effort
                        )
                    } label: {
                        HStack(spacing: OfficialUISpec.Spacing.p8) {
                            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                                Text(option.name)
                                    .font(OfficialUISpec.Typography.sStrong14)
                                if let description = option.description {
                                    Text(description)
                                        .font(OfficialUISpec.Typography.xxs12)
                                        .foregroundStyle(OfficialUISpec.Token.caption)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: OfficialUISpec.Spacing.p0)
                            if selected {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .disabled(sessionStore.isSelectingModel)
                    .accessibilityLabel(option.name)
                    .accessibilityValue(selected ? t("menu.effort") : "")
                }
            }
        } else {
            Text(t("empty.efforts"))
        }
    }

    private func rootCell(label: String, value: String) -> some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            Text(label)
                .font(OfficialUISpec.Typography.s14)
            Spacer(minLength: OfficialUISpec.Spacing.p0)
            Text(value)
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.caption)
                .lineLimit(1)
            OfficialAssetImage(name: "icon-chevron-down", template: true)
                .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                .foregroundStyle(OfficialUISpec.Token.caption)
        }
    }

    private struct EffortOption: Identifiable {
        let id: String
        let effort: String?
        let name: String
        let description: String?
    }

    private func effortOptions(for model: CoreSessionModelDirectory.Model) -> [EffortOption] {
        var result: [EffortOption] = []
        if model.defaultReasoningEffort == nil {
            result.append(.init(id: "provider-default", effort: nil, name: t("effort.providerDefault"), description: nil))
        }
        result.append(contentsOf: model.reasoningEfforts.map {
            .init(id: $0.id, effort: $0.id, name: $0.name, description: $0.description)
        })
        return result
    }

    /// Every product-facing string is resolved from the locked RC8
    /// `ui-model-selection` catalog. A missing entry fails closed to its key.
    private func t(_ key: String, replacements: [String: String] = [:]) -> String {
        Self.localizedValue(key: key, language: language, replacements: replacements)
    }

    static func localizedValue(
        key: String,
        language: String,
        replacements: [String: String] = [:]
    ) -> String {
        var value = OfficialUISpec.LocaleCatalog.value(
            namespace: "ui-model-selection",
            key: key,
            language: language
        ) ?? key
        for (token, replacement) in replacements {
            value = value.replacingOccurrences(of: "{\(token)}", with: replacement)
        }
        return value
    }
}
