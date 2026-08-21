import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Write-only provider credential control. The literal lives only in a local
/// `SecureField` until the single typed set callback consumes it; the observable
/// credential store exposes Host-safe configured/source/writable metadata only.
struct NativeProviderCredentialForm: View {
    let reference: String
    let credential: CredentialViewDTO
    let setCredential: (String, String) async -> Bool
    let unsetCredential: (String) async -> Bool

    @State private var enteredValue = ""
    @State private var inFlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            Text(official("keyInput"))
                .font(OfficialUISpec.Typography.xsStrong13)
            Text(NativeCredentialStatusPresentation.statusText(credential))
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.caption)
            if credential.writable {
                SecureField(official("keyPlaceholder"), text: $enteredValue)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: OfficialUISpec.Spacing.p8) {
                    Button(inFlight ? official("applying") : official("apply")) {
                        Task { await save() }
                    }
                    .disabled(inFlight || enteredValue.isEmpty)
                    if credential.configured {
                        Button(official("remove")) {
                            Task { await remove() }
                        }
                        .disabled(inFlight)
                    }
                }
            }
        }
    }

    private func save() async {
        let value = enteredValue
        guard !value.isEmpty else { return }
        inFlight = true
        defer { inFlight = false }
        if await setCredential(reference, value) {
            enteredValue = ""
        }
    }

    private func remove() async {
        inFlight = true
        defer { inFlight = false }
        _ = await unsetCredential(reference)
    }

    private func official(_ key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: key, language: "en") ?? ""
    }
}
