#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Readback-safe credential presentation. A `CredentialViewDTO` has no raw
/// value field; this projection deliberately preserves that property while
/// deriving only official status copy and editability.
enum NativeCredentialStatusPresentation {
    static func isEditable(_ credential: CredentialViewDTO) -> Bool {
        credential.writable
    }

    static func statusText(_ credential: CredentialViewDTO) -> String {
        if !credential.writable {
            return official(key: "keyEnvLocked")
        }
        if credential.configured {
            return official(key: "keyStored")
        }
        return official(key: "keyPlaceholderNative")
    }

    private static func official(key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-settings-models", key: key, language: "en") ?? ""
    }
}
