import Foundation

struct SupportedHostBuildCatalog: Codable, Sendable {
    struct Build: Codable, Sendable, Equatable {
        let id: String
        let officialSourceCommit: String
        let dshPackageVersion: String
        let webFrontendPackageVersion: String
        let nodeRuntimeVersion: String
        let minimumMacOS: String
        let ciRunner: String
        let minimumXcodeMajor: Int
        let protocolFixtureRevision: String
        let uiSpecRevision: String
        let supportedArchitectures: [String]
        let verifiedAt: String?
        let verificationState: String
    }

    let schemaVersion: Int
    let defaultBuildId: String
    let builds: [Build]
}

enum HostBuildVerification: Equatable, Sendable {
    case supported(SupportedHostBuildCatalog.Build)
    case unsupported(reason: String)
}

struct HostBuildVerifier: Sendable {
    private let catalog: SupportedHostBuildCatalog

    init(catalog: SupportedHostBuildCatalog) {
        self.catalog = catalog
    }

    static func bundled(decoder: JSONDecoder = JSONDecoder()) throws -> HostBuildVerifier {
        guard let url = Bundle.main.url(forResource: "SupportedHostBuilds", withExtension: "json") else {
            throw HostBuildVerifierError.missingCatalog
        }
        return try HostBuildVerifier(catalog: decoder.decode(SupportedHostBuildCatalog.self, from: Data(contentsOf: url)))
    }

    func verify(runtime: HostRuntimeConfiguration, fileManager: FileManager = .default) -> HostBuildVerification {
        guard fileManager.isExecutableFile(atPath: runtime.nodeExecutable.path) else {
            return .unsupported(reason: "Bundled Node runtime is missing or not executable.")
        }
        guard fileManager.fileExists(atPath: runtime.dshEntrypoint.path) else {
            return .unsupported(reason: "Bundled DeepSeek Harness entrypoint is missing.")
        }
        guard let build = catalog.builds.first(where: { $0.id == catalog.defaultBuildId }) else {
            return .unsupported(reason: "The bundled Host catalog has no default build.")
        }
        guard build.dshPackageVersion == "0.1.0-rc.6", build.webFrontendPackageVersion == "0.1.0-rc.6" else {
            return .unsupported(reason: "Bundled Host catalog does not match the fixed payload contract.")
        }
        return .supported(build)
    }
}

enum HostBuildVerifierError: LocalizedError {
    case missingCatalog

    var errorDescription: String? {
        switch self {
        case .missingCatalog: return "Supported DeepSeek Harness Host build catalog is missing."
        }
    }
}
