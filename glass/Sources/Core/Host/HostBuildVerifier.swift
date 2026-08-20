import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif
struct SupportedHostBuildCatalog: Codable, Sendable {
    struct Build: Codable, Sendable, Equatable {
        let id: String
        let officialSourceCommit: String
        let dshPackageVersion: String
        let webFrontendPackageVersion: String
        let nodeRuntimeVersion: String
        let minimumAppVersion: String
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
    case verified(SupportedHostBuildCatalog.Build)
    case unverified(reason: String)
    case unsupported(reason: String)
}

struct HostBuildVerifier: Sendable {
    private struct PackageManifest: Decodable {
        let version: String
    }

    private static let lockedOfficialSourceCommit = "141eb6fef83422698aef7a981029e843e8161534"
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
            return .unverified(reason: "The bundled Host catalog has no default build.")
        }
        guard build.officialSourceCommit == Self.lockedOfficialSourceCommit else {
            return .unverified(reason: "Bundled Host catalog does not match the locked official source commit.")
        }
        guard !build.dshPackageVersion.isEmpty,
              !build.webFrontendPackageVersion.isEmpty,
              !build.nodeRuntimeVersion.isEmpty,
              !build.protocolFixtureRevision.isEmpty,
              !build.uiSpecRevision.isEmpty,
              !build.minimumAppVersion.isEmpty else {
            return .unverified(reason: "Bundled Host catalog is missing fixed payload support metadata.")
        }

        let dshPackageRoot = runtime.dshEntrypoint
            .deletingLastPathComponent() // lib
            .deletingLastPathComponent() // @deepseek-ai/dsh
        let nodeModulesRoot = dshPackageRoot
            .deletingLastPathComponent() // @deepseek-ai
            .deletingLastPathComponent() // node_modules
        let dshManifestURL = dshPackageRoot.appendingPathComponent("package.json")
        let webManifestURL = nodeModulesRoot
            .appendingPathComponent("@deepseek-ai/dsh-web-frontend/package.json")

        guard let dshVersion = packageVersion(at: dshManifestURL), dshVersion == build.dshPackageVersion else {
            return .unverified(reason: "Bundled dsh package version does not match the supported Host catalog.")
        }
        guard let webVersion = packageVersion(at: webManifestURL), webVersion == build.webFrontendPackageVersion else {
            return .unverified(reason: "Bundled dsh web frontend version does not match the supported Host catalog.")
        }
        guard build.verificationState == "verified" else {
            return .unverified(reason: "Bundled Host build is awaiting the required macOS CI verification.")
        }
        return .verified(build)
    }

    private func packageVersion(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(PackageManifest.self, from: data) else {
            return nil
        }
        return manifest.version
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
