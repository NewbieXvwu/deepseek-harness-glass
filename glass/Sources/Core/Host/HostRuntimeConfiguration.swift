import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif
struct HostRuntimeConfiguration: Sendable {
    let nodeExecutable: URL
    let dshEntrypoint: URL
    let homeDirectory: URL
    let logFile: URL

    static func bundled(fileManager: FileManager = .default) throws -> HostRuntimeConfiguration {
        guard let resources = Bundle.main.resourceURL else {
            throw HostRuntimeConfigurationError.missingBundleResources
        }
        let node = resources.appendingPathComponent("node/node")
        let entrypoint = resources.appendingPathComponent("backend/node_modules/@deepseek-ai/dsh/lib/bin.js")
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DeepSeekHarnessGlass", isDirectory: true)
        let home = supportRoot.appendingPathComponent("dsh", isDirectory: true)
        let logs = supportRoot.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        return HostRuntimeConfiguration(
            nodeExecutable: node,
            dshEntrypoint: entrypoint,
            homeDirectory: home,
            logFile: logs.appendingPathComponent("host.log")
        )
    }
}

enum HostRuntimeConfigurationError: LocalizedError {
    case missingBundleResources

    var errorDescription: String? {
        switch self {
        case .missingBundleResources: return "DeepSeek Harness application resources are unavailable."
        }
    }
}
