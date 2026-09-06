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
    @Published private(set) var state: HostLifecycleState = .idle {
        didSet {
            guard oldValue != state else { return }
            let transition = HostLifecycleTransition(from: oldValue, to: state, at: Date())
            stateTransitions.append(transition)
            if stateTransitions.count > 200 { stateTransitions.removeFirst(stateTransitions.count - 200) }
            appendLog("[host] transition \(transition.summary)")
            if case let .ready(connection) = oldValue {
                Task {
                    await connection.context.remote.closeStreams()
                    connection.context.authenticatedHost.invalidate()
                }
            }
            Task { [diagnostics] in await diagnostics.recordLifecycle(state, ownedPID: process?.processIdentifier) }
        }
    }
    @Published private(set) var recentLogLines: [String] = []
    @Published private(set) var stateTransitions: [HostLifecycleTransition] = []

    private let runtime: HostRuntimeConfiguration
    private let verifier: HostBuildVerifier
    private let fileManager: FileManager
    private let diagnostics: HostDiagnosticRecorder
    private var process: Process?
    private var outputPipe: Pipe?
    private var announcedOutput = ""
    private var recoveryAttempts = 0
    private static let announcementRescanLookbackUTF16 = 1_024
    private static let announcementRegularExpression: NSRegularExpression = {
        // This is compile-once state: Host stderr can arrive in many short
        // chunks during startup, so compiling this expression per chunk causes
        // avoidable work precisely on the readiness critical path.
        try! NSRegularExpression(pattern: #"dsh web:\s+(https?://127\.0\.0\.1(?::\d+)?/?\S*)"#)
    }()
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
        self.diagnostics = HostDiagnosticRecorder(dshHome: runtime.homeDirectory.path)
        self.startupTimeoutNanoseconds = startupTimeoutNanoseconds
    }

    convenience init() throws {
        try self.init(runtime: .bundled(), verifier: .bundled())
    }

    deinit {
        verificationTask?.cancel()
        startupTimeoutTask?.cancel()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? activeLogHandle?.close()
        if process?.isRunning == true { process?.terminate() }
    }

    var endpoint: URL? { state.endpoint }
    var logFile: URL { runtime.logFile }
    var homeDirectory: URL { runtime.homeDirectory }
    var ownedProcessIdentifier: Int32? { process?.processIdentifier }

    func diagnosticSnapshot() async -> HostDiagnosticSnapshot {
        await diagnostics.snapshot()
    }

    func start() {
        guard process == nil else {
            appendLog("[host] start reused existing owned process pid=\(process?.processIdentifier ?? 0)")
            return
        }
        let verification = verifier.verify(runtime: runtime, fileManager: fileManager)
        switch verification {
        case let .bestEffort(build, reason):
            appendLog("[host] best-effort build candidate: \(reason)")
            launch(build: build, verification: verification)
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
            launch(build: build, verification: verification)
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

    private func launch(build: SupportedHostBuildCatalog.Build, verification: HostBuildVerification) {
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
        state = .starting
        let process = Process()
        HarnessHostProcess.owned(runtime: runtime).apply(to: process)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.consumeHostOutput(text, build: build, verification: verification) }
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

    private func consumeHostOutput(_ text: String, build: SupportedHostBuildCatalog.Build, verification: HostBuildVerification) {
        appendLog(text)
        let previousUTF16Length = (announcedOutput as NSString).length
        announcedOutput += text
        // Limit retained parsing data while preserving a complete startup line.
        let wasTrimmed: Bool
if announcedOutput.count > 32_768 {
            announcedOutput.removeFirst(announcedOutput.count - 16_384)
            wasTrimmed = true
        } else {
            wasTrimmed = false
        }
        // A valid announcement may straddle two stderr chunks. Rescan only a
        // bounded tail across the boundary; after a retention trim, the new
        // buffer is itself the complete bounded window.
        let searchStart = wasTrimmed
            ? 0
            : max(0, previousUTF16Length - Self.announcementRescanLookbackUTF16)
        guard case .starting = state,
              let launchURL = Self.announcedEndpoint(in: announcedOutput, fromUTF16Offset: searchStart) else { return }
        let descriptor: HostLaunchDescriptor
        do {
            descriptor = try HostLaunchDescriptor(url: launchURL)
        } catch {
            state = .failed(HostFailure(
                kind: .verificationFailed,
                message: "DeepSeek Harness Host announced an invalid rc.1 launch URL.",
                exitStatus: nil,
                logPath: runtime.logFile.path
            ))
            terminateAfterVerificationFailure()
            return
        }
        announcedOutput = ""
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        state = .authenticating(descriptor.cleanBaseURL)
        verify(descriptor: descriptor, build: build, verification: verification)
    }

    /// Parses only the bounded append window selected by `consumeHostOutput`.
    /// Internal visibility permits deterministic XCTest coverage of split and
    /// malformed announcements without introducing a mock Host text protocol.
    static func announcedEndpoint(in output: String, fromUTF16Offset offset: Int = 0) -> URL? {
        let nsOutput = output as NSString
        guard offset >= 0, offset <= nsOutput.length else { return nil }
        let range = NSRange(location: offset, length: nsOutput.length - offset)
        guard let match = announcementRegularExpression.firstMatch(in: output, range: range),
              match.numberOfRanges >= 2,
              match.range(at: 1).location != NSNotFound
        else { return nil }
        let rawURL = nsOutput.substring(with: match.range(at: 1))
        guard let endpoint = URL(string: rawURL),
              endpoint.scheme == "http",
              endpoint.host == "127.0.0.1",
              endpoint.user == nil,
              endpoint.password == nil,
              let port = endpoint.port,
              port > 0 else { return nil }
        return endpoint
    }

    private func verify(
        descriptor: HostLaunchDescriptor,
        build: SupportedHostBuildCatalog.Build,
        verification: HostBuildVerification
    ) {
        verificationTask?.cancel()
        verificationTask = Task { [weak self] in
            do {
                let authenticatedHost = try await HostAuthBootstrap.authenticate(descriptor)
                guard !Task.isCancelled else { return }
                self?.state = .connecting(authenticatedHost.baseURL)
                let remote = RemoteConnection(authenticatedHost: authenticatedHost)
                let events = try await remote.connectEvents()
                guard !Task.isCancelled else {
                    await remote.closeStreams()
                    authenticatedHost.invalidate()
                    return
                }
                guard let self else {
                    await remote.closeStreams()
                    authenticatedHost.invalidate()
                    return
                }
                self.state = .classifying(authenticatedHost.baseURL)
                // rc.1 `$events.ready` proves the authenticated Remote generation and
                // carries Host `home`; it intentionally exposes no build/version field.
                // Build identity therefore comes from the trusted installation source,
                // while assurance is published only after this handshake succeeds.
                let compatibility: HostCompatibility
                switch verification {
                case .verified:
                    compatibility = .verified
                case let .bestEffort(_, reason):
                    compatibility = .bestEffort(reason: reason)
                case let .unsupported(reason):
                    throw HostBuildClassificationError.unsupportedAfterHandshake(reason)
                }
                let endpoint = authenticatedHost.baseURL
                await self.diagnostics.recordConnected(
                    build: build,
                    compatibility: compatibility,
                    endpoint: endpoint,
                    pid: self.process?.processIdentifier,
                    generation: events.generation
                )
                let context = HostConnectionContext(
                    authenticatedHost: authenticatedHost,
                    remote: remote,
                    events: events,
                    compatibility: compatibility,
                    diagnostics: self.diagnostics
                )
                self.state = .ready(HostConnection(
                    endpoint: endpoint,
                    build: build,
                    compatibility: compatibility,
                    context: context,
                    startedAt: Date(),
                    diagnostics: self.diagnostics
                ))
                self.appendLog("[host] remote ready endpoint=\(endpoint.absoluteString) build=\(build.id)")
            } catch {
                guard !Task.isCancelled else { return }
                if let self { await self.diagnostics.recordRPCError(error) }
                self?.state = .failed(HostFailure(
                    kind: .verificationFailed,
                    message: "DeepSeek Harness Host started but could not authenticate or establish Remote readiness: \(error.localizedDescription)",
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
        let kind: HostFailure.Kind
        if case .ready = state {
            kind = .unexpectedTermination
        } else {
            kind = .terminatedBeforeReady
        }
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
                  case .starting = self.state else { return }
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
        let normalized = Self.redactSecrets(in: text.trimmingCharacters(in: .newlines))
        guard !normalized.isEmpty else { return }
        recentLogLines.append(contentsOf: normalized.split(separator: "\n").map(String.init))
        if recentLogLines.count > 200 { recentLogLines.removeFirst(recentLogLines.count - 200) }
        let line = "\(Self.logTimestampFormatter.string(from: Date())) \(normalized)\n"
        guard let data = line.data(using: .utf8) else { return }
        writeLog(data)
    }

    static func redactSecrets(in text: String) -> String {
        var value = text.replacingOccurrences(
            of: #"(?i)([?&]token=)[^&\s]+"#,
            with: "$1<redacted>",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)(authorization:\s*bearer\s+)[^\s]+"#,
            with: "$1<redacted>",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)(cookie:\s*)[^\r\n]+"#,
            with: "$1<redacted>",
            options: .regularExpression
        )
        return value
    }

    /// Shared timestamp formatter. `appendLog` runs on the main actor only, so a
    /// static instance is safe and avoids allocating a formatter per log line.
    private static let logTimestampFormatter = ISO8601DateFormatter()

    /// Lazy persistent write handle for the owned log file. Kept for the
    /// controller lifetime so a long stderr stream never opens and closes the
    /// file (and rebuilds append state) per line.
    private var activeLogHandle: FileHandle?

    private func writeLog(_ data: Data) {
        do {
            if activeLogHandle == nil, fileManager.fileExists(atPath: runtime.logFile.path) {
                activeLogHandle = try FileHandle(forWritingTo: runtime.logFile)
            }
            if let handle = activeLogHandle {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                // First line, or the file was replaced externally (log rotation):
                // fall back to atomic replacement until the new file exists.
                try data.write(to: runtime.logFile, options: .atomic)
            }
        } catch {
            Task { [diagnostics] in await diagnostics.recordRPCError(error) }
            fputs("[HostLog] writeLog failed: \(error.localizedDescription)\n", stderr)
        }
    }
}

private enum HostBuildClassificationError: LocalizedError {
    case unsupportedAfterHandshake(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedAfterHandshake(reason): return reason
        }
    }
}
