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
    case bestEffort(SupportedHostBuildCatalog.Build, reason: String)
    case unsupported(reason: String)
}

/// Pre-connection facts for one launch candidate. Keeping the package versions
/// here lets the controller validate a runnable local payload before launch while
/// deferring compatibility classification until authenticated Remote readiness.
struct HostBuildCandidate: Equatable, Sendable {
    let build: SupportedHostBuildCatalog.Build
    let dshVersion: String?
    let webFrontendVersion: String?
}

enum HostBuildPreparation: Equatable, Sendable {
    case candidate(HostBuildCandidate)
    case unsupported(reason: String)
}

struct HostBuildVerifier: Sendable {
    private struct PackageManifest: Decodable {
        let version: String
    }

    private let catalog: SupportedHostBuildCatalog
    private let classifier: HostBuildClassifier

    init(catalog: SupportedHostBuildCatalog, classifier: HostBuildClassifier = HostBuildClassifier()) {
        self.catalog = catalog
        self.classifier = classifier
    }

    static func bundled(decoder: JSONDecoder = JSONDecoder()) throws -> HostBuildVerifier {
        guard let url = Bundle.main.url(forResource: "SupportedHostBuilds", withExtension: "json") else {
            throw HostBuildVerifierError.missingCatalog
        }
        return try HostBuildVerifier(catalog: decoder.decode(SupportedHostBuildCatalog.self, from: Data(contentsOf: url)))
    }

    /// Performs only checks that can be known before a Host is contacted: the
    /// bundled runtime must be launchable and the selected catalog entry must be
    /// structurally valid. Package versions are captured as candidate facts but
    /// do not become a compatibility decision here.
    func prepare(runtime: HostRuntimeConfiguration, fileManager: FileManager = .default) -> HostBuildPreparation {
        guard fileManager.isExecutableFile(atPath: runtime.nodeExecutable.path) else {
            return .unsupported(reason: "Bundled Node runtime is missing or not executable.")
        }
        guard fileManager.fileExists(atPath: runtime.dshEntrypoint.path) else {
            return .unsupported(reason: "Bundled DeepSeek Harness entrypoint is missing.")
        }
        guard let build = catalog.builds.first(where: { $0.id == catalog.defaultBuildId }) else {
            return .unsupported(reason: "The bundled Host catalog has no default build.")
        }
        if let reason = classifier.catalogValidationError(for: build) {
            return .unsupported(reason: reason)
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

        return .candidate(HostBuildCandidate(
            build: build,
            dshVersion: packageVersion(at: dshManifestURL),
            webFrontendVersion: packageVersion(at: webManifestURL)
        ))
    }

    /// Called only after the rc.1 authentication and Remote-ready handshake have
    /// succeeded. The same entry point is reusable by an external Attach/Adopt
    /// path when it can supply package facts from that installation.
    func classify(candidate: HostBuildCandidate) -> HostBuildVerification {
        classifier.classify(
            build: candidate.build,
            dshVersion: candidate.dshVersion,
            webFrontendVersion: candidate.webFrontendVersion
        )
    }

    /// Compatibility shim for focused verifier tests and non-lifecycle callers.
    /// Lifecycle code must use `prepare` followed by post-handshake `classify`.
    func verify(runtime: HostRuntimeConfiguration, fileManager: FileManager = .default) -> HostBuildVerification {
        switch prepare(runtime: runtime, fileManager: fileManager) {
        case let .candidate(candidate):
            return classify(candidate: candidate)
        case let .unsupported(reason):
            return .unsupported(reason: reason)
        }
    }

    private func packageVersion(at url: URL) -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return nil
        }
        do {
            let manifest = try JSONDecoder().decode(PackageManifest.self, from: data)
            return manifest.version
        } catch {
            return nil
        }
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
