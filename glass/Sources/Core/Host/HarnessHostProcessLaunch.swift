import Foundation

/// Immutable launch facts for an owned rc.1 Host process. The executable is
/// always the Node binary resolved from the selected runtime resources; PATH is
/// never consulted to find Node or dsh.
struct HarnessHostProcessLaunch: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]

    static func owned(
        runtime: HostRuntimeConfiguration,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HarnessHostProcessLaunch {
        var environment = inheritedEnvironment
        environment["DSH_HOME"] = runtime.homeDirectory.path
        return .init(
            executableURL: runtime.nodeExecutable,
            arguments: ["--expose-internals", runtime.dshEntrypoint.path, "web", "--port", "0"],
            environment: environment
        )
    }

    func apply(to process: Process) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
    }
}
