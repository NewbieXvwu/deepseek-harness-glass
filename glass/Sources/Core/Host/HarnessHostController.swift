import Combine
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif
/// Main-actor owner for the bundled local DeepSeek Harness Host. It deliberately
/// exposes a lifecycle state rather than a Web URL because the native app uses
/// RPC/SSE, not an embedded browser surface.
@MainActor
final class HarnessHostController: ObservableObject {
    @Published private(set) var state: HostLifecycleState = .idle
    @Published private(set) var recentLogLines: [String] = []

    private let runtime: HostRuntimeConfiguration
    private let verifier: HostBuildVerifier
    private let fileManager: FileManager
    private var process: Process?
    private var outputPipe: Pipe?
    private var announcedOutput = ""
    private var recoveryAttempts = 0
    private var verificationTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var suppressRecoveryForTermination = false
    private var restartAfterTermination = false
    private let startupTimeoutNanoseconds: UInt64

    init(
        runtime: HostRuntimeConfiguration,
        verifier: HostBuildVerifier,
        fileManager: FileManager = .default,
        startupTimeoutNanoseconds: UInt64 = 20_000_000_000
    ) {
        self.runtime = runtime
        self.verifier = verifier
        self.fileManager = fileManager
        self.startupTimeoutNanoseconds = startupTimeoutNanoseconds
    }

    convenience init() throws {
        try self.init(runtime: .bundled(), verifier: .bundled())
    }

    deinit {
        verificationTask?.cancel()
        startupTimeoutTask?.cancel()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }

    var endpoint: URL? { state.endpoint }
    var logFile: URL { runtime.logFile }
    var homeDirectory: URL { runtime.homeDirectory }
    var ownedProcessIdentifier: Int32? { process?.processIdentifier }

    func start() {
        guard process == nil else {
            appendLog("[host] start reused existing owned process pid=\(process?.processIdentifier ?? 0)")
            return
        }
        switch verifier.verify(runtime: runtime, fileManager: fileManager) {
        case let .unverified(reason):
            state = .unverified(HostUnverified(
                reason: reason,
                developerWriteOverrideEnabled: false,
                logPath: runtime.logFile.path
            ))
            appendLog("[host] unverified write-protected: \(reason)")
            return
        case let .unsupported(reason):
            state = .failed(HostFailure(
                kind: .invalidBundledBaseline,
                message: reason,
                exitStatus: nil,
                logPath: runtime.logFile.path
            ))
            return
        case let .verified(build):
            guard OfficialUISpec.Build.isCompatible(with: build.id),
                  build.officialSourceCommit == OfficialUISpec.Build.sourceCommit,
                  build.uiSpecRevision == OfficialUISpec.Build.uiSpecRevision
            else {
                state = .failed(HostFailure(
                    kind: .invalidBundledBaseline,
                    message: "Bundled Host build does not match the generated Official UI specification.",
                    exitStatus: nil,
                    logPath: runtime.logFile.path
                ))
                return
            }
            launch(build: build)
        }
    }

    func retryOnce() {
        guard recoveryAttempts == 0 else { return }
        recoveryAttempts = 1
        state = .recovering(attempt: recoveryAttempts)
        if let process, process.isRunning {
            suppressRecoveryForTermination = false
            restartAfterTermination = true
            appendLog("[host] manual retry terminating owned pid=\(process.processIdentifier)")
            process.terminate()
        } else {
            start()
        }
    }

    func stop() {
        verificationTask?.cancel()
        verificationTask = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        suppressRecoveryForTermination = true
        restartAfterTermination = false
        state = .stopping
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        if let process, process.isRunning {
            appendLog("[host] stopping owned pid=\(process.processIdentifier)")
            process.terminate()
        } else {
            self.process = nil
            state = .idle
        }
    }

    private func launch(build: SupportedHostBuildCatalog.Build) {
        guard fileManager.isExecutableFile(atPath: runtime.nodeExecutable.path) else {
            state = .failed(HostFailure(
                kind: .missingNodeRuntime,
                message: "Bundled Node runtime is missing or not executable.",
                exitStatus: nil,
                logPath: runtime.logFile.path
            ))
            return
        }
        guard fileManager.fileExists(atPath: runtime.dshEntrypoint.path) else {
            state = .failed(HostFailure(
                kind: .missingPayload,
                message: "Bundled DeepSeek Harness Host payload is missing.",
                exitStatus: nil,
                logPath: runtime.logFile.path
            ))
            return
        }

        do {
            try fileManager.createDirectory(at: runtime.homeDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: runtime.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            state = .failed(HostFailure(
                kind: .launchFailed,
                message: "Could not prepare DeepSeek Harness runtime directories: \(error.localizedDescription)",
                exitStatus: nil,
                logPath: runtime.logFile.path
            ))
            return
        }

        announcedOutput = ""
        suppressRecoveryForTermination = false
        state = .startingOwned
        let process = Process()
        process.executableURL = runtime.nodeExecutable
        process.arguments = ["--expose-internals", runtime.dshEntrypoint.path, "web", "--port", "0"]
        var environment = ProcessInfo.processInfo.environment
        environment["DSH_HOME"] = runtime.homeDirectory.path
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.consumeHostOutput(text, build: build) }
        }
        process.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in self?.handleTermination(terminated) }
        }

        do {
            try process.run()
            self.process = process
            self.outputPipe = pipe
            appendLog("[host] started build=\(build.id) pid=\(process.processIdentifier)")
            armStartupTimeout(for: process)
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            state = .failed(HostFailure(
                kind: .launchFailed,
                message: "Could not launch bundled DeepSeek Harness Host: \(error.localizedDescription)",
                exitStatus: nil,
                logPath: runtime.logFile.path
            ))
        }
    }

    private func consumeHostOutput(_ text: String, build: SupportedHostBuildCatalog.Build) {
        appendLog(text)
        announcedOutput += text
        // Limit retained parsing data while preserving a complete startup line.
        if announcedOutput.count > 32_768 { announcedOutput.removeFirst(announcedOutput.count - 16_384) }
        guard state.endpoint == nil,
              let range = announcedOutput.range(
                of: #"dsh web:\s+(https?://127\.0\.0\.1(?::\d+)?/?\S*)"#,
                options: .regularExpression
              ) else { return }
        let announcement = String(announcedOutput[range])
        guard let rawURL = announcement.split(separator: " ").last.map(String.init),
              let endpoint = URL(string: rawURL),
              endpoint.scheme == "http",
              endpoint.host == "127.0.0.1",
              endpoint.port != nil else {
            appendLog("[host] ignored malformed endpoint announcement")
            return
        }
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        state = .verifying(endpoint)
        verify(endpoint: endpoint, build: build)
    }

    private func verify(endpoint: URL, build: SupportedHostBuildCatalog.Build) {
        verificationTask?.cancel()
        verificationTask = Task { [weak self] in
            do {
                let transport = DSHClientTransport(
                    baseURL: endpoint,
                    accessPolicy: HostRPCAccessPolicy(trust: .verified(build))
                )
                let response = try await transport.call(method: "host.describe", payload: .object([:]))
                guard case .success = response.result else {
                    throw DSHTransportError.decoding("host.describe returned a business error")
                }
                guard !Task.isCancelled else { return }
                self?.state = .ready(HostConnection(endpoint: endpoint, build: build, startedAt: Date()))
                self?.appendLog("[host] verified endpoint=\(endpoint.absoluteString) build=\(build.id)")
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed(HostFailure(
                    kind: .verificationFailed,
                    message: "DeepSeek Harness Host started but could not complete host.describe verification: \(error.localizedDescription)",
                    exitStatus: nil,
                    logPath: self?.runtime.logFile.path ?? ""
                ))
                self?.terminateAfterVerificationFailure()
            }
        }
    }

    private func handleTermination(_ process: Process) {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        self.process = nil
        verificationTask?.cancel()
        verificationTask = nil
        let terminationStatus = process.terminationStatus
        appendLog("[host] terminated pid=\(process.processIdentifier) code=\(terminationStatus)")
        if suppressRecoveryForTermination {
            suppressRecoveryForTermination = false
            if case .stopping = state { state = .idle }
            return
        }
        if restartAfterTermination {
            restartAfterTermination = false
            state = .recovering(attempt: recoveryAttempts)
            appendLog("[host] retrying after requested restart attempt=\(recoveryAttempts)")
            start()
            return
        }
        let kind: HostFailure.Kind = state.endpoint == nil ? .terminatedBeforeReady : .unexpectedTermination
        let failure = HostFailure(
            kind: kind,
            message: "DeepSeek Harness Host terminated with code \(terminationStatus).",
            exitStatus: terminationStatus,
            logPath: runtime.logFile.path
        )
        if recoveryAttempts == 0 {
            recoveryAttempts = 1
            state = .recovering(attempt: recoveryAttempts)
            appendLog("[host] automatic recovery attempt=1 after \(kind.rawValue)")
            start()
        } else {
            state = .failed(failure)
        }
    }

    private func armStartupTimeout(for process: Process) {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = Task { [weak self, weak process] in
            try? await Task.sleep(nanoseconds: self?.startupTimeoutNanoseconds ?? 0)
            guard !Task.isCancelled, let self, let process, self.process === process,
                  self.state.endpoint == nil else { return }
            self.state = .failed(HostFailure(
                kind: .endpointNotAnnounced,
                message: "DeepSeek Harness Host did not announce a loopback endpoint before startup timeout.",
                exitStatus: nil,
                logPath: self.runtime.logFile.path
            ))
            self.appendLog("[host] startup announcement timed out pid=\(process.processIdentifier)")
            self.terminateAfterVerificationFailure()
        }
    }

    private func terminateAfterVerificationFailure() {
        suppressRecoveryForTermination = true
        if let process, process.isRunning { process.terminate() }
    }

    private func appendLog(_ text: String) {
        let normalized = text.trimmingCharacters(in: .newlines)
        guard !normalized.isEmpty else { return }
        recentLogLines.append(contentsOf: normalized.split(separator: "\n").map(String.init))
        if recentLogLines.count > 200 { recentLogLines.removeFirst(recentLogLines.count - 200) }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(normalized)\n"
        guard let data = line.data(using: .utf8) else { return }
        if fileManager.fileExists(atPath: runtime.logFile.path), let handle = try? FileHandle(forWritingTo: runtime.logFile) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: runtime.logFile, options: .atomic)
        }
    }
}
