import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Versioned upstream DOM/SlotMap/ModuleLoader contract generated from the
/// locked official source. Runtime code consumes this only as a diagnostic and
/// safety assertion; it never reads local Swift source to infer a boundary.
enum OfficialGhostPlaneContract {
    struct Fixture: Decodable, Equatable, Sendable {
        struct Source: Decodable, Equatable, Sendable {
            let path: String
            let sha256: String
        }

        struct Slot: Decodable, Equatable, Sendable {
            let name: String
            let kind: String
            let scope: String
        }

        struct ModuleLoader: Decodable, Equatable, Sendable {
            let bootGlobal: String
            let registrationGlobal: String
            let registrationMethod: String
            let singleResourcePathTemplate: String
            let comboPathTemplate: String
            let bootBatchPhases: [String]
            let initialURLFromBatches: Bool
            let factoryRegistration: Bool
        }

        let schemaVersion: Int
        let sourceCommit: String
        let sources: [Source]
        let selectors: [String]
        let slots: [Slot]
        let moduleLoader: ModuleLoader
    }

    enum ValidationError: Swift.Error, Equatable, Sendable {
        case missingResource
        case incompatibleFixture
        case skeletonSelectorDrift(missing: [String], unexpected: [String])
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
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        guard fixture.schemaVersion == 1,
              fixture.sourceCommit == OfficialUISpec.Build.sourceCommit,
              fixture.sources.count >= 8,
              !fixture.sources.contains(where: { $0.path.isEmpty || !$0.sha256.hasPrefix("sha256:") }),
              !fixture.selectors.isEmpty,
              !fixture.slots.isEmpty,
              fixture.moduleLoader == .init(
                bootGlobal: "__DSH_BOOT__",
                registrationGlobal: "__ModuleLoader__",
                registrationMethod: "load",
                singleResourcePathTemplate: "/plugins/??<id>/client.js&rev=<rev>",
                comboPathTemplate: "/plugins/??<id1>/client.js,<id2>/client.js&rev=<rev>",
                bootBatchPhases: ["bootstrap", "application"],
                initialURLFromBatches: true,
                factoryRegistration: true
              )
        else {
            throw ValidationError.incompatibleFixture
        }
        return fixture
    }

    static func validateSkeletonSelectors(_ selectors: [String], against fixture: Fixture) throws {
        let actual = Set(selectors)
        let expected = Set(fixture.selectors)
        let missing = expected.subtracting(actual).sorted()
        let unexpected = actual.subtracting(expected).sorted()
        guard missing.isEmpty, unexpected.isEmpty else {
            throw ValidationError.skeletonSelectorDrift(missing: missing, unexpected: unexpected)
        }
    }
}
