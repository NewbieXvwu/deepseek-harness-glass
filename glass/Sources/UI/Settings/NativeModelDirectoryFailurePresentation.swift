#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Renderer-safe projection of Host model-directory failures. It deliberately
/// has no transport error, endpoint, request or credential fields: only the
/// Host-returned failure data can be presented to the native settings surface.
struct NativeModelDirectoryFailurePresentation: Equatable, Identifiable {
    let id: String
    let name: String
    let message: String

    static let title = OfficialUISpec.LocaleCatalog.value(
        namespace: "ui-settings-models",
        key: "loadFailed",
        language: "en"
    ) ?? ""

    static func project(_ failures: [LLMModelFailureDTO]) -> [Self] {
        failures.map { .init(id: $0.id, name: $0.name, message: $0.message) }
    }
}
