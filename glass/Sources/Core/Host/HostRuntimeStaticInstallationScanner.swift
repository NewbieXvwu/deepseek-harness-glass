import Foundation

/// Finds static Harness installations only when they reproduce the app's
/// complete, reviewable resource layout. Build trust is intentionally separate:
/// callers must still parse and verify the discovered catalog before choosing
/// an Adopt plan.
struct HostRuntimeStaticInstallationScanner: Sendable {
    struct Candidate: Equatable, Sendable {
        let resourcesRoot: URL
        let nodeExecutable: URL
        let dshEntrypoint: URL
        let supportedBuildsCatalog: URL
    }

    func scan(resourcesRoots: [URL], fileManager: FileManager = .default) -> [Candidate] {
        var seen: Set<String> = []
        return resourcesRoots.compactMap { root in
            let canonical = root.standardizedFileURL
            guard seen.insert(canonical.path).inserted else { return nil }
            let node = canonical.appendingPathComponent("node/node")
            let entrypoint = canonical.appendingPathComponent("backend/node_modules/@deepseek-ai/dsh/lib/bin.js")
            let catalog = canonical.appendingPathComponent("SupportedHostBuilds.json")
            guard fileManager.isExecutableFile(atPath: node.path),
                  fileManager.fileExists(atPath: entrypoint.path),
                  fileManager.fileExists(atPath: catalog.path)
            else { return nil }
            return .init(resourcesRoot: canonical, nodeExecutable: node, dshEntrypoint: entrypoint, supportedBuildsCatalog: catalog)
        }
    }
}
