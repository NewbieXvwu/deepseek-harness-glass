import Foundation

extension OfficialUISpec {
    enum LocaleCatalog {
        private struct Document: Decodable {
            let schemaVersion: Int
            let languages: [String]
            let entries: [Entry]
        }

        private struct Entry: Decodable {
            let namespace: String
            let key: String
            let language: String
            let value: String
        }

        private static let document: Document = {
            guard let url = resourceBundle.url(forResource: "official-locales", withExtension: "json") else {
                fatalError("official-locales.json is missing from GlassSpec resources")
            }
            do {
                let decoded = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
                guard decoded.schemaVersion == 1 else {
                    fatalError("unsupported official locale schema \(decoded.schemaVersion)")
                }
                return decoded
            } catch {
                fatalError("official locale catalog is invalid: \(error)")
            }
        }()

        static let supportedLanguages = Set(document.languages)
        static let values: [String: String] = Dictionary(
            uniqueKeysWithValues: document.entries.map {
                ("\($0.language)|\($0.namespace).\($0.key)", $0.value)
            }
        )

        static func contains(namespace: String, key: String, language: String) -> Bool {
            values["\(language)|\(namespace).\(key)"] != nil
        }

        static func value(namespace: String, key: String, language: String) -> String? {
            values["\(language)|\(namespace).\(key)"]
        }

        private static var resourceBundle: Bundle {
#if SWIFT_PACKAGE
            .module
#else
            .main
#endif
        }
    }
}
