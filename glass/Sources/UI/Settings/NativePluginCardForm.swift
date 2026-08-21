import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native form chrome for one reviewed built-in plugin namespace. It owns only
/// ephemeral staged text; all durable writes return through the shell callback.
struct NativePluginCardForm: View {
    let card: NativeBuiltinPluginCard
    let namespace: SettingsNamespaceDTO
    let writable: Bool
    @ObservedObject var credentialStore: NativeCredentialStore
    let refreshCredential: (String) async -> Void
    let setCredential: (String, String) async -> Bool
    let save: (NativePluginCardDraft) async -> Bool

    @State private var expanded = false
    @State private var draft: NativePluginCardDraft
    @State private var saving = false
    @State private var saveFailed = false
    @State private var credentialText = ""
    @State private var savingCredential = false

    init(
        card: NativeBuiltinPluginCard,
        namespace: SettingsNamespaceDTO,
        writable: Bool,
        credentialStore: NativeCredentialStore,
        refreshCredential: @escaping (String) async -> Void,
        setCredential: @escaping (String, String) async -> Bool,
        save: @escaping (NativePluginCardDraft) async -> Bool
    ) {
        self.card = card
        self.namespace = namespace
        self.writable = writable
        self.credentialStore = credentialStore
        self.refreshCredential = refreshCredential
        self.setCredential = setCredential
        self.save = save
        _draft = State(initialValue: .init(namespace: namespace, fields: card.fields))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                        Text(card.title)
                        Text(card.description)
                            .font(OfficialUISpec.Typography.xs13)
                            .foregroundStyle(OfficialUISpec.Token.caption)
                    }
                    Spacer()
                    if draft.isDirty {
                        Text(official("unsaved"))
                            .font(OfficialUISpec.Typography.xs13)
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if !writable {
                    Text(official("readOnly"))
                        .accessibilityAddTraits(.isStaticText)
                }
                ForEach(card.fields, id: \.path) { field in
                    fieldControl(field)
                }
                if let credential = webSearchCredential {
                    credentialControl(credential)
                }
                if draft.hasInvalidDraft {
                    Text(official("invalidNumber"))
                }
                if saveFailed {
                    Text(official("saveFailed"))
                }
                HStack {
                    Button(official("save")) { persist() }
                        .disabled(!writable || !draft.isDirty || draft.hasInvalidDraft || saving)
                    Button(official("discard")) {
                        draft.discard()
                        saveFailed = false
                    }
                    .disabled(!draft.isDirty || saving)
                }
            }
        }
        .onChange(of: namespace.revision) { _, _ in
            draft = .init(namespace: namespace, fields: card.fields)
            saveFailed = false
        }
        .task(id: webSearchCredential?.reference) {
            if let reference = webSearchCredential?.reference {
                await refreshCredential(reference)
            }
        }
    }

    @ViewBuilder
    private func fieldControl(_ field: NativePluginCardField) -> some View {
        if let state = draft.state(for: field) {
            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                TextField(card.label(for: field), text: binding(for: field))
                    .disabled(!writable || saving)
                Text(card.hint(for: field))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                if state.overridden {
                    HStack {
                        Text(official("overridden"))
                            .font(OfficialUISpec.Typography.xs13)
                        Button(official("reset")) {
                            draft.reset(field)
                            saveFailed = false
                        }
                        .disabled(!writable || saving)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func credentialControl(_ presentation: NativeWebSearchCredentialPresentation) -> some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            SecureField(modelsOfficial("keyInput"), text: $credentialText)
                .disabled(!presentation.writable || savingCredential)
            if let view = credentialStore.view(for: presentation.reference) {
                Text(NativeCredentialStatusPresentation.statusText(view))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            } else {
                Text(modelsOfficial("keyPlaceholderNative"))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
            Button(official("save")) { persistCredential(presentation.reference) }
                .disabled(!presentation.writable || credentialText.isEmpty || savingCredential)
        }
    }

    private var webSearchCredential: NativeWebSearchCredentialPresentation? {
        guard card == .webSearch,
              let base = NativeWebSearchCredentialPresentation.project(namespace: namespace, credential: nil)
        else { return nil }
        return NativeWebSearchCredentialPresentation.project(
            namespace: namespace,
            credential: credentialStore.view(for: base.reference)
        )
    }

    private func binding(for field: NativePluginCardField) -> Binding<String> {
        .init(
            get: { draft.state(for: field)?.text ?? "" },
            set: { text in
                draft.stage(text, for: field)
                saveFailed = false
            }
        )
    }

    private func persistCredential(_ reference: String) {
        let value = credentialText
        savingCredential = true
        Task {
            let accepted = await setCredential(reference, value)
            await MainActor.run {
                savingCredential = false
                saveFailed = !accepted
                if accepted { credentialText = "" }
            }
        }
    }

    private func persist() {
        let submitting = draft
        saving = true
        saveFailed = false
        Task {
            let accepted = await save(submitting)
            await MainActor.run {
                saving = false
                saveFailed = !accepted
                if accepted {
                    draft = .init(namespace: namespace, fields: card.fields)
                }
            }
        }
    }

    private func official(_ key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-plugins", key: key, language: "en") ?? ""
    }

    private func modelsOfficial(_ key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: key, language: "en") ?? ""
    }
}
