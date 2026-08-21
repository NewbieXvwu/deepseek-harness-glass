#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Readback-safe projection for the web-search card's credential seam. It
/// mirrors the official controller: the settings namespace chooses a reference,
/// while the credentials domain supplies only configured/writable facts.
struct NativeWebSearchCredentialPresentation: Equatable {
    static let namespace = "web-search-deepseek"
    static let defaultReference = "DEEPSEEK_API_KEY"

    let reference: String
    let configured: Bool
    let writable: Bool

    static func project(
        namespace: SettingsNamespaceDTO,
        credential: CredentialViewDTO?
    ) -> Self? {
        guard namespace.ns == Self.namespace else { return nil }
        let declared = namespace.value.objectValue?["apiKeyEnv"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = (declared?.isEmpty == false) ? declared! : defaultReference
        return .init(
            reference: reference,
            configured: credential?.configured ?? false,
            // An unknown credential ref remains writable until Host proves
            // otherwise; this does not claim a secret exists or will be saved.
            writable: credential?.writable ?? true
        )
    }
}
