import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native root for the official settings surface. It deliberately renders only
/// the typed Host descriptor and never synthesizes a writable field from a
/// missing schema/value pair.
struct NativeSettingsRoot: View {
    enum SectionID: String, CaseIterable, Identifiable {
        case general
        case models
        case plugins

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: NativeSettingsRoot.official(namespace: "ui-settings-general", key: "general.nav")
            case .models: NativeSettingsRoot.official(namespace: "ui-settings-models", key: "nav")
            case .plugins: NativeSettingsRoot.official(namespace: "ui-settings-plugins", key: "nav")
            }
        }
    }

    @ObservedObject var store: NativeSettingsStore
    let retry: () -> Void
    let close: () -> Void
    /// Typed actions owned by the shell; the view cannot access transport.
    let selectTheme: (CoreThemePreference) -> Void
    @ObservedObject var credentialStore: NativeCredentialStore
    @ObservedObject var modelDirectoryStore: NativeModelDirectoryStore
    let refreshModelDirectory: () async -> Void
    let refreshCredential: (String) async -> Void
    let setCredential: (String, String) async -> Bool
    let savePluginCard: (NativePluginCardDraft) async -> Bool
    @State private var selection: SectionID? = .general

    var body: some View {
        NavigationSplitView {
            List(SectionID.allCases, selection: $selection) { section in
                Text(section.title).tag(Optional(section))
            }
            .navigationTitle(official(namespace: "ui-settings-general", key: "title"))
        } detail: {
            detail
        }
        .frame(minWidth: 620, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(official(namespace: "ui-settings-plugins", key: "collapse"), action: close)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView(official(namespace: "locale", key: "loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: OfficialUISpec.Spacing.p12) {
                Text(official(namespace: "locale", key: "load.failed"))
                Button(official(namespace: "locale", key: "retry"), action: retry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if selection == .models {
                modelsDetail
            } else if selection == .plugins {
                let cards = NativeBuiltinPluginCard.dispatched(from: store.namespaces)
                List {
                    if cards.isEmpty {
                        Text(official(namespace: "ui-settings-plugins", key: "empty"))
                    } else {
                        ForEach(cards) { card in
                            if let namespace = store.namespaces.first(where: { $0.ns == card.namespace }) {
                                NativePluginCardForm(
                                    card: card,
                                    namespace: namespace,
                                    writable: store.writable,
                                    credentialStore: credentialStore,
                                    refreshCredential: refreshCredential,
                                    setCredential: setCredential,
                                    save: savePluginCard
                                )
                            }
                        }
                    }
                }
            } else if selection == .general, store.themePreference.status == .ready {
                List {
                    Section(official(namespace: "ui-theme", key: "appearance.title")) {
                        HStack(spacing: OfficialUISpec.Spacing.p8) {
                            ForEach(CoreThemePreference.allCases, id: \.rawValue) { preference in
                                Button {
                                    selectTheme(preference)
                                } label: {
                                    Text(official(namespace: "ui-theme", key: "appearance." + preference.rawValue))
                                }
                                .buttonStyle(.bordered)
                                .disabled(!store.themePreference.writable)
                                .accessibilityAddTraits(store.themePreference.current == preference ? .isSelected : [])
                            }
                        }
                    }
                }
            } else {
                List {
                    Section(selection?.title ?? SectionID.general.title) {
                        ForEach(store.namespaces, id: \.ns) { namespace in
                            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                                Text(namespace.ns)
                                Text(namespace.applies)
                                    .font(OfficialUISpec.Typography.xs13)
                                    .foregroundStyle(OfficialUISpec.Token.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modelsDetail: some View {
        switch modelDirectoryStore.phase {
        case .idle, .loading:
            ProgressView(official(namespace: "locale", key: "loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: OfficialUISpec.Spacing.p12) {
                Text(NativeModelDirectoryFailurePresentation.title)
                Button(official(namespace: "ui-settings-models", key: "retry")) {
                    Task { await refreshModelDirectory() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            List {
                Section(official(namespace: "ui-settings-models", key: "provider")) {
                    ForEach(modelDirectoryStore.providers) { provider in
                        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                            Text(provider.displayName)
                            Text(provider.settingsNs)
                                .font(OfficialUISpec.Typography.xs13)
                                .foregroundStyle(OfficialUISpec.Token.caption)
                        }
                    }
                }
                Section(official(namespace: "ui-settings-models", key: "models")) {
                    ForEach(modelDirectoryStore.groups) { group in
                        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                            Text(group.name)
                            Text(group.models.map(\.name).joined(separator: ", "))
                                .font(OfficialUISpec.Typography.xs13)
                                .foregroundStyle(OfficialUISpec.Token.caption)
                        }
                    }
                }
                if !modelDirectoryStore.failures.isEmpty {
                    Section(NativeModelDirectoryFailurePresentation.title) {
                        ForEach(modelDirectoryStore.failures) { failure in
                            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                                Text(failure.name)
                                Text(failure.message)
                                    .font(OfficialUISpec.Typography.xs13)
                                    .foregroundStyle(OfficialUISpec.Token.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func official(namespace: String, key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: namespace, key: key, language: "en") ?? ""
    }
}
