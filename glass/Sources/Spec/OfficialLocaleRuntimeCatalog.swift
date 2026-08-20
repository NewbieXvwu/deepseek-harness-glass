import Foundation

/// Runtime-readable counterpart to the generated locale value table. It keeps
/// provenance validation on packaged structured data rather than treating the
/// generated Swift implementation as a text artifact.
struct OfficialLocaleRuntimeCatalog: Decodable {
    struct Entry: Decodable, Equatable {
        let id: String
        let namespace: String
        let key: String
        let language: String
        let value: String
        let interpolationParameters: [String]
        let pluralCategory: String?
    }

    let schemaVersion: Int
    let sourceCommit: String
    let localeRevision: String
    let sourceInputRevision: String
    let languages: [String]
    let entries: [Entry]

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }

    static let catalog: OfficialLocaleRuntimeCatalog = {
        guard let url = resourceBundle.url(forResource: "official-locales", withExtension: "json") else {
            preconditionFailure("Missing packaged official locale catalog")
        }
        do {
            let decoded = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            precondition(decoded.schemaVersion == 1, "Unsupported official locale catalog schema")
            precondition(!decoded.entries.isEmpty, "Official locale catalog is empty")
            return decoded
        } catch {
            preconditionFailure("Unable to decode packaged official locale catalog: \(error)")
        }
    }()

    var valueMap: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.map { ("\($0.language)|\($0.namespace).\($0.key)", $0.value) })
    }
}
