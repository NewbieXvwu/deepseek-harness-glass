import Foundation
import XCTest

@testable import GlassCore

@MainActor
final class ExternalHarnessHostControllerTests: XCTestCase {
    func testAttachesThroughPrintedLaunchURLWithoutOwningProcess() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let nodePath = environment["DSH_GLASS_HOST_NODE"],
              let entrypointPath = environment["DSH_GLASS_HOST_ENTRY"] else {
            throw XCTSkip("External Host test requires DSH_GLASS_HOST_NODE and DSH_GLASS_HOST_ENTRY")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-glass-external-host-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: URL(fileURLWithPath: nodePath),
            dshEntrypoint: URL(fileURLWithPath: entrypointPath),
            homeDirectory: root.appendingPathComponent("dsh", isDirectory: true),
            logFile: root.appendingPathComponent("owned-host.log")
        )
        let outputURL = root.appendingPathComponent("external-host.stdout")
        XCTAssertTrue(FileManager.default.createFile(atPath: outputURL.path, contents: nil))
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let process = Process()
        HarnessHostProcess.owned(runtime: runtime).apply(to: process)
        process.standardOutput = output
        process.standardError = output
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let launchURL = try await waitForLaunchURL(at: outputURL, timeout: 30)
        let controller = ExternalHarnessHostController()
        defer { controller.stop() }
        controller.attach(launchURL: launchURL)
        let connection = try await waitForReady(controller, timeout: 30)
        let diagnostics = await connection.diagnostics.snapshot()

        XCTAssertEqual(connection.endpoint.scheme, "http")
        XCTAssertEqual(connection.endpoint.host, "127.0.0.1")
        XCTAssertEqual(diagnostics.ownership, "external")
        XCTAssertNil(diagnostics.ownedProcessID)

        controller.stop()
        XCTAssertTrue(process.isRunning, "stopping an external Host connection must not terminate its process")
    }

    func testRejectsCleanEndpointWithoutLaunchToken() throws {
        let controller = ExternalHarnessHostController()
        controller.attach(launchURL: try XCTUnwrap(URL(string: "http://127.0.0.1:43123/")))

        guard case let .failed(failure) = controller.state else {
            return XCTFail("clean endpoint must not enter external authentication")
        }
        XCTAssertEqual(failure.kind, .verificationFailed)
    }

    private func waitForLaunchURL(at url: URL, timeout: TimeInterval) async throws -> URL {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               let launchURL = HarnessHostController.announcedEndpoint(in: text) {
                return launchURL
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("external Host did not print a launch URL")
        throw ExternalHostTestError.timeout
    }

    private func waitForReady(_ controller: ExternalHarnessHostController, timeout: TimeInterval) async throws -> HostConnection {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case let .ready(connection) = controller.state { return connection }
            if case let .failed(failure) = controller.state {
                XCTFail("external Host failed: \(failure.message)")
                throw ExternalHostTestError.failed
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("external Host did not reach ready")
        throw ExternalHostTestError.timeout
    }

    private enum ExternalHostTestError: Error { case failed, timeout }
}
