import Foundation

enum OfficialGhostPlaneContract {
    struct Fixture: Decodable, Equatable, Sendable {
        struct Slot: Decodable, Equatable, Sendable {
            let name: String
            let kind: String
            let scope: String
            let sourcePath: String
            let anchor: String
            let zone: String
        }

        let slots: [Slot]
    }

    enum ValidationError: Swift.Error, Equatable, Sendable {
        case missingResource
    }

    static func load() throws -> Fixture {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = .main
        #endif
        guard let url = bundle.url(forResource: "official-ghost-plane-contract", withExtension: "json") else {
            throw ValidationError.missingResource
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}
