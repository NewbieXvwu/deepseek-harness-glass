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
        case agentPresets

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: NativeSettingsRoot.official(namespace: "ui-settings-general", key: "general.nav")
            case .models: NativeSettingsRoot.official(namespace: "ui-settings-models", key: "nav")
            case .plugins: NativeSettingsRoot.official(namespace: "ui-settings-plugins", key: "nav")
            case .agentPresets: NativeSettingsRoot.official(namespace: "ui-agent-preset", key: "nav")
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
    @ObservedObject var modelDiscoveryStore: NativeModelDiscoveryStore
    @ObservedObject var agentPresetStore: NativeAgentPresetStore
    let refreshModelDirectory: () async -> Void
    let discoverModels: (LLMDiscoverModelsRequest) async -> Void
    let adoptDiscoveredModels: ([LLMDiscoveredModelDTO], Set<String>, LLMProviderDTO) async -> Bool
    let refreshAgentPresets: () async -> Void
    let readAgentPreset: (String) async -> Bool
    let openAgentPresetDocument: (String) async -> Bool
    let copyAgentPreset: (AgentPresetCopyRequest) async -> Bool
    let removeAgentPreset: (String) async -> Bool
    let selectAgentPresetDefault: (AgentPresetEntryDTO) async -> Bool
    let refreshCredential: (String) async -> Void
    let refreshCredentials: ([String]) async -> Void
    let setCredential: (String, String) async -> Bool
    let unsetCredential: (String) async -> Bool
    let savePluginCard: (NativePluginCardDraft) async -> Bool
    @State private var selection: SectionID? = .general
    @State private var copySource: AgentPresetEntryDTO?
    @State private var copyID = ""
    @State private var copyName = ""
    @State private var copyInFlight = false
    @State private var pendingDelete: AgentPresetEntryDTO?
    @State private var deleteInFlight = false
    @State private var discoveryProvider: LLMProviderDTO?
    @State private var selectedDiscoveredModelIDs: Set<String> = []
    @State private var discoveryAdoptionInFlight = false

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
            } else if selection == .agentPresets {
                agentPresetsDetail
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
    private var agentPresetsDetail: some View {
        switch agentPresetStore.phase {
        case .idle, .loading:
            ProgressView(official(namespace: "ui-agent-preset", key: "loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: OfficialUISpec.Spacing.p12) {
                Text(official(namespace: "ui-agent-preset", key: "error"))
                Button(official(namespace: "ui-agent-preset", key: "retry")) {
                    Task { await refreshAgentPresets() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            List {
                Text(official(namespace: "ui-agent-preset", key: "sectionIntro"))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
        case .ready:
            List {
                Section(official(namespace: "ui-agent-preset", key: "title")) {
                    Text(official(namespace: "ui-agent-preset", key: "sectionIntro"))
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    ForEach(agentPresetStore.presets) { preset in
                        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                            HStack {
                                Text(preset.name ?? preset.id)
                                if preset.broken != nil {
                                    Text(official(namespace: "ui-agent-preset", key: "brokenBadge"))
                                        .font(OfficialUISpec.Typography.xs13)
                                        .foregroundStyle(OfficialUISpec.Token.caption)
                                }
                            }
                            Text(preset.description ?? official(namespace: "ui-agent-preset", key: "noDescription"))
                                .font(OfficialUISpec.Typography.xs13)
                                .foregroundStyle(OfficialUISpec.Token.caption)
                            Text(preset.id)
                                .font(OfficialUISpec.Typography.xs13.monospaced())
                                .foregroundStyle(OfficialUISpec.Token.caption)
                            HStack(spacing: OfficialUISpec.Spacing.p8) {
                                if preset.trust == "system", preset.broken == nil {
                                    Button(official(namespace: "ui-agent-preset", key: "view")) {
                                        Task { _ = await readAgentPreset(preset.id) }
                                    }
                                }
                                if preset.trust == "user" {
                                    Button(official(namespace: "ui-agent-preset", key: agentPresetStore.hasDocument ? "openLocation" : "showLocation")) {
                                        Task { _ = await openAgentPresetDocument(preset.id) }
                                    }
                                }
                                Button(official(namespace: "ui-agent-preset", key: "duplicate")) {
                                    copySource = preset
                                    copyID = ""
                                    copyName = ""
                                }
                                .disabled(!agentPresetStore.authorable || preset.broken != nil)
                                if !preset.isDefault, preset.broken == nil {
                                    Button(official(namespace: "ui-agent-preset", key: "setDefault")) {
                                        Task { _ = await selectAgentPresetDefault(preset) }
                                    }
                                    .disabled(!store.agentPresetDefault.writable)
                                }
                                if preset.trust == "user" {
                                    Button(official(namespace: "ui-agent-preset", key: "delete"), role: .destructive) {
                                        pendingDelete = preset
                                    }
                                }
                            }
                            if let path = agentPresetStore.revealedPaths[preset.id] {
                                Text(official(namespace: "ui-agent-preset", key: "revealedPathLabel") + " " + path)
                                    .font(OfficialUISpec.Typography.xs13)
                                    .textSelection(.enabled)
                                    .foregroundStyle(OfficialUISpec.Token.caption)
                            }
                        }
                    }
                }
                if let detail = agentPresetStore.detail {
                    Section(official(namespace: "ui-agent-preset", key: "composition")) {
                        Text(detail.content)
                            .font(OfficialUISpec.Typography.xs13.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .sheet(item: $copySource) { source in
                copySheet(source: source)
            }
            .confirmationDialog(
                official(namespace: "ui-agent-preset", key: "deleteTitle"),
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(official(namespace: "ui-agent-preset", key: "cancel"), role: .cancel) {
                    pendingDelete = nil
                }
                Button(deleteInFlight ? official(namespace: "ui-agent-preset", key: "deleting") : official(namespace: "ui-agent-preset", key: "deleteConfirm"), role: .destructive) {
                    guard let pendingDelete else { return }
                    deleteInFlight = true
                    Task {
                        let removed = await removeAgentPreset(pendingDelete.id)
                        deleteInFlight = false
                        if removed { self.pendingDelete = nil }
                    }
                }
                .disabled(deleteInFlight)
            } message: {
                Text(official(namespace: "ui-agent-preset", key: "deleteDescription"))
            }
        }
    }

    private func copySheet(source: AgentPresetEntryDTO) -> some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p12) {
            Text(official(namespace: "ui-agent-preset", key: "copyIntro"))
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.caption)
            Text(official(namespace: "ui-agent-preset", key: "copyOf") + " " + (source.name ?? source.id))
            TextField(official(namespace: "ui-agent-preset", key: "presetId"), text: $copyID, prompt: Text(official(namespace: "ui-agent-preset", key: "presetIdPlaceholder")))
            TextField(official(namespace: "ui-agent-preset", key: "displayName"), text: $copyName, prompt: Text(official(namespace: "ui-agent-preset", key: "displayNamePlaceholder")))
            HStack {
                Button(official(namespace: "ui-agent-preset", key: "cancel")) {
                    copySource = nil
                }
                Spacer()
                Button(copyInFlight ? official(namespace: "ui-agent-preset", key: "creating") : official(namespace: "ui-agent-preset", key: "create")) {
                    let request = AgentPresetCopyRequest(
                        from: source.id,
                        agentPreset: copyID,
                        name: copyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : copyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    copyInFlight = true
                    Task {
                        let copied = await copyAgentPreset(request)
                        if copied { _ = await openAgentPresetDocument(request.agentPreset) }
                        copyInFlight = false
                        if copied { copySource = nil }
                    }
                }
                .disabled(!copyIDIsSubmittable || copyInFlight)
            }
        }
        .padding(OfficialUISpec.Spacing.p16)
        .frame(minWidth: 440)
    }

    private var copyIDIsSubmittable: Bool {
        guard !copyID.isEmpty,
              copyID.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil
        else { return false }
        return !agentPresetStore.presets.contains(where: { $0.id == copyID })
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
                            Button(official(namespace: "ui-settings-models", key: "fetchModels")) {
                                beginModelDiscovery(for: provider)
                            }
                            .disabled(!store.writable)
                            if let reference = NativeProviderCredentialReferencePresentation.reference(
                                for: provider,
                                namespaces: store.namespaces
                            ), let credential = credentialStore.view(for: reference) {
                                NativeProviderCredentialForm(
                                    reference: reference,
                                    credential: credential,
                                    setCredential: setCredential,
                                    unsetCredential: unsetCredential
                                )
                            }
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
            .task(id: providerCredentialReferences) {
                await refreshCredentials(providerCredentialReferences)
            }
            .sheet(item: $discoveryProvider) { provider in
                modelDiscoveryPicker(for: provider)
            }
            .onChange(of: modelDiscoveryStore.phase) { _, phase in
                guard phase == .ready,
                      let provider = discoveryProvider,
                      let namespace = store.namespaces.first(where: { $0.ns == provider.settingsNs })
                else { return }
                selectedDiscoveredModelIDs = NativeDiscoveredModelSelection.initiallySelectedIDs(
                    candidates: modelDiscoveryStore.candidates,
                    existingModels: NativeDiscoveredModelSelection.models(
                        in: namespace,
                        providerPath: provider.settingsPath
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func modelDiscoveryPicker(for provider: LLMProviderDTO) -> some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p12) {
            Text(official(namespace: "ui-settings-models", key: "fetchTitle"))
                .font(OfficialUISpec.Typography.baseStrong16)
            switch modelDiscoveryStore.phase {
            case .idle, .loading:
                ProgressView(official(namespace: "locale", key: "loading"))
            case .empty:
                Text(official(namespace: "ui-settings-models", key: "fetchEmpty"))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            case .failed:
                Text(official(namespace: "ui-settings-models", key: "loadFailed"))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            case .ready:
                List(modelDiscoveryStore.candidates) { candidate in
                    Toggle(isOn: selectedCandidateBinding(candidate.id)) {
                        Text(candidate.name ?? candidate.id)
                    }
                }
                HStack(spacing: OfficialUISpec.Spacing.p8) {
                    Button(allDiscoveredCandidatesSelected
                        ? official(namespace: "ui-settings-models", key: "fetchDeselectAll")
                        : official(namespace: "ui-settings-models", key: "fetchSelectAll")) {
                        toggleAllDiscoveredCandidates()
                    }
                    Spacer()
                    Button(official(namespace: "ui-settings-models", key: "cancel")) {
                        dismissModelDiscovery()
                    }
                    Button(official(namespace: "ui-settings-models", key: "fetchAdopt")) {
                        Task { await adoptCurrentDiscoveredModels(for: provider) }
                    }
                    .disabled(discoveryAdoptionInFlight || selectedDiscoveredModelIDs.isEmpty)
                }
            }
        }
        .padding(OfficialUISpec.Spacing.p16)
        .frame(minWidth: 420, minHeight: 240)
    }

    private var allDiscoveredCandidatesSelected: Bool {
        !modelDiscoveryStore.candidates.isEmpty
            && modelDiscoveryStore.candidates.allSatisfy { selectedDiscoveredModelIDs.contains($0.id) }
    }

    private func selectedCandidateBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedDiscoveredModelIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedDiscoveredModelIDs.insert(id)
                } else {
                    selectedDiscoveredModelIDs.remove(id)
                }
            }
        )
    }

    private func toggleAllDiscoveredCandidates() {
        if allDiscoveredCandidatesSelected {
            selectedDiscoveredModelIDs = []
        } else {
            selectedDiscoveredModelIDs = Set(modelDiscoveryStore.candidates.map(\.id))
        }
    }

    private func beginModelDiscovery(for provider: LLMProviderDTO) {
        discoveryProvider = provider
        selectedDiscoveredModelIDs = []
        Task {
            await discoverModels(.init(
                settingsNs: provider.settingsNs,
                provider: provider.provider,
                baseURL: nil,
                api: nil,
                apiKey: nil
            ))
        }
    }

    private func dismissModelDiscovery() {
        discoveryProvider = nil
        selectedDiscoveredModelIDs = []
        modelDiscoveryStore.dismiss()
    }

    private func adoptCurrentDiscoveredModels(for provider: LLMProviderDTO) async {
        discoveryAdoptionInFlight = true
        defer { discoveryAdoptionInFlight = false }
        let adopted = await adoptDiscoveredModels(
            modelDiscoveryStore.candidates,
            selectedDiscoveredModelIDs,
            provider
        )
        if adopted { dismissModelDiscovery() }
    }

    private var providerCredentialReferences: [String] {
        NativeProviderCredentialReferencePresentation.references(
            for: modelDirectoryStore.providers,
            namespaces: store.namespaces
        )
    }

    private static func official(namespace: String, key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: namespace, key: key, language: "en") ?? ""
    }
}
