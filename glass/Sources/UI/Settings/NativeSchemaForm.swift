import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// A native-only renderer for one `NativeUIManifest` that has already passed
/// `NativeUIManifestVerifier`. It accepts no closures, scripts, markup, or
/// plugin-provided views: every control is selected from the closed SwiftUI
/// field-kind enum and submits typed settings operations to the Host boundary.
struct NativeSchemaForm: View {
    let manifest: NativeUIManifest
    let namespace: SettingsNamespaceDTO
    let writable: Bool
    @ObservedObject var credentialStore: NativeCredentialStore
    let refreshCredential: (String) async -> Void
    let setCredential: (String, String) async -> Bool
    let save: ([SettingsPathOperationDTO]) async -> Bool

    @State private var draft: NativeSchemaFormDraft
    @State private var secretDrafts: [String: String] = [:]
    @State private var saving = false
    @State private var savingSecretIDs: Set<String> = []
    @State private var saveFailed = false

    init(
        manifest: NativeUIManifest,
        namespace: SettingsNamespaceDTO,
        writable: Bool,
        credentialStore: NativeCredentialStore,
        refreshCredential: @escaping (String) async -> Void,
        setCredential: @escaping (String, String) async -> Bool,
        save: @escaping ([SettingsPathOperationDTO]) async -> Bool
    ) {
        self.manifest = manifest
        self.namespace = namespace
        self.writable = writable
        self.credentialStore = credentialStore
        self.refreshCredential = refreshCredential
        self.setCredential = setCredential
        self.save = save
        _draft = State(initialValue: .init(namespace: namespace, manifest: manifest))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p12) {
            ForEach(manifest.sections.sorted(by: { $0.order < $1.order }), id: \.id) { section in
                sectionView(section)
            }
            if !manifest.secretRoles.isEmpty {
                secretSection
            }
            formActions
        }
        .onChange(of: namespace.revision) { _, _ in
            draft = .init(namespace: namespace, manifest: manifest)
            secretDrafts = [:]
            saveFailed = false
        }
        .task(id: manifest.secretRoles.map(\.credentialReference)) {
            for role in manifest.secretRoles {
                await refreshCredential(role.credentialReference)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: NativeUIManifest.Section) -> some View {
        let groups = section.groupIDs.compactMap(group)
        let groupedFieldIDs = Set(groups.flatMap(\.fieldIDs))
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Text(localized(section.titleKey))
                .font(OfficialUISpec.Typography.baseStrong16)
            ForEach(section.fieldIDs.filter { !groupedFieldIDs.contains($0) }, id: \.self) { id in
                if let field = field(id) { fieldControl(field) }
            }
            ForEach(groups, id: \.id) { group in
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
                    if let titleKey = group.titleKey {
                        Text(localized(titleKey))
                            .font(OfficialUISpec.Typography.s14)
                    }
                    ForEach(group.fieldIDs, id: \.self) { id in
                        if let field = field(id) { fieldControl(field) }
                    }
                }
                .padding(OfficialUISpec.Spacing.p8)
                .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized(section.titleKey))
    }

    @ViewBuilder
    private func fieldControl(_ field: NativeUIManifest.Field) -> some View {
        if let state = draft.state(for: field, writable: writable) {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            switch field.kind {
            case .toggle:
                Toggle(localized(field.labelKey), isOn: booleanBinding(for: field))
                    .disabled(!state.writable || saving)
            case .select:
                Picker(localized(field.labelKey), selection: textBinding(for: field)) {
                    Text(placeholder(for: field)).tag("")
                    ForEach(field.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .disabled(!state.writable || saving)
            case .readOnly:
                LabeledContent(localized(field.labelKey)) {
                    Text(state.text.isEmpty ? placeholder(for: field) : state.text)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .textSelection(.enabled)
                }
            case .text, .number, .path:
                TextField(localized(field.labelKey), text: textBinding(for: field))
                    .disabled(!state.writable || saving)
            case .secret:
                // The verifier forbids secret fields. SecretRole controls below
                // use a separate write-only credentials API instead.
                EmptyView()
            }
            if let helpKey = field.helpKey {
                Text(localized(helpKey))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
            if state.invalid {
                Text(localized("invalidNumber"))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
            }
            if state.overridden, manifest.actions.contains(.reset) {
                Button(localized("reset")) {
                    draft.reset(field)
                    saveFailed = false
                }
                .disabled(!state.writable || saving)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized(field.labelKey))
        }
    }

    private var secretSection: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            ForEach(manifest.secretRoles, id: \.id) { role in
                let reference = role.credentialReference
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                    SecureField(localized(role.labelKey), text: secretBinding(for: role))
                        .disabled(!writable || savingSecretIDs.contains(role.id))
                    if let view = credentialStore.view(for: reference) {
                        Text(NativeCredentialStatusPresentation.statusText(view))
                            .font(OfficialUISpec.Typography.xs13)
                            .foregroundStyle(OfficialUISpec.Token.caption)
                    }
                    if manifest.actions.contains(.save) {
                        Button(localized("save")) { persistSecret(role) }
                            .disabled(
                                !writable
                                || (secretDrafts[role.id] ?? "").isEmpty
                                || savingSecretIDs.contains(role.id)
                            )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var formActions: some View {
        if manifest.actions.contains(.save) || manifest.actions.contains(.discard) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                if manifest.actions.contains(.save) {
                    Button(localized("save")) { persist() }
                        .disabled(!writable || !draft.isDirty || draft.hasInvalidDraft || saving)
                }
                if manifest.actions.contains(.discard) {
                    Button(localized("discard")) {
                        draft.discard()
                        secretDrafts = [:]
                        saveFailed = false
                    }
                    .disabled((!draft.isDirty && secretDrafts.isEmpty) || saving)
                }
                if saveFailed {
                    Text(localized("saveFailed"))
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                }
            }
        }
    }

    private func field(_ id: String) -> NativeUIManifest.Field? {
        manifest.fields.first(where: { $0.id == id })
    }

    private func group(_ id: String) -> NativeUIManifest.Group? {
        manifest.groups.first(where: { $0.id == id })
    }

    private func textBinding(for field: NativeUIManifest.Field) -> Binding<String> {
        .init(
            get: { draft.state(for: field, writable: writable)?.text ?? "" },
            set: {
                draft.stageText($0, for: field)
                saveFailed = false
            }
        )
    }

    private func booleanBinding(for field: NativeUIManifest.Field) -> Binding<Bool> {
        .init(
            get: { draft.state(for: field, writable: writable)?.boolean ?? false },
            set: {
                draft.stageBoolean($0, for: field)
                saveFailed = false
            }
        )
    }

    private func secretBinding(for role: NativeUIManifest.SecretRole) -> Binding<String> {
        .init(
            get: { secretDrafts[role.id] ?? "" },
            set: { secretDrafts[role.id] = $0 }
        )
    }

    private func persist() {
        guard let plan = draft.mutationPlan, !plan.isEmpty else { return }
        saving = true
        saveFailed = false
        Task {
            let accepted = await save(plan)
            await MainActor.run {
                saving = false
                saveFailed = !accepted
                if accepted { draft = .init(namespace: namespace, manifest: manifest) }
            }
        }
    }

    private func persistSecret(_ role: NativeUIManifest.SecretRole) {
        let value = secretDrafts[role.id] ?? ""
        guard !value.isEmpty else { return }
        savingSecretIDs.insert(role.id)
        Task {
            let accepted = await setCredential(role.credentialReference, value)
            await MainActor.run {
                savingSecretIDs.remove(role.id)
                saveFailed = !accepted
                if accepted { secretDrafts[role.id] = "" }
            }
        }
    }

    private func localized(_ key: String) -> String {
        for resource in manifest.localeResources {
            if let value = OfficialUISpec.LocaleCatalog.value(namespace: resource.namespace, key: key, language: "en") {
                return value
            }
        }
        return OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-plugins", key: key, language: "en") ?? key
    }

    private func placeholder(for field: NativeUIManifest.Field) -> String {
        field.options.first ?? "—"
    }
}
