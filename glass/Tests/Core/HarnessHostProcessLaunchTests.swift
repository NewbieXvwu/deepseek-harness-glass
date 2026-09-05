import XCTest
@testable import GlassCore

final class HarnessHostProcessLaunchTests: XCTestCase {
    func testOwnedLaunchUsesBundledNodeWithoutPATHResolution() {
        let runtime = HostRuntimeConfiguration(
            nodeExecutable: URL(fileURLWithPath: "/App/Contents/Resources/node/node"),
            dshEntrypoint: URL(fileURLWithPath: "/App/Contents/Resources/backend/node_modules/@deepseek-ai/dsh/lib/bin.js"),
            homeDirectory: URL(fileURLWithPath: "/tmp/glass-dsh-home"),
            logFile: URL(fileURLWithPath: "/tmp/glass-host.log")
        )
        let launch = HarnessHostProcessLaunch.owned(
            runtime: runtime,
            inheritedEnvironment: ["PATH": "", "HOME": "/tmp/fake-user"]
        )

        XCTAssertEqual(launch.executableURL, runtime.nodeExecutable)
        XCTAssertEqual(launch.arguments, [
            "--expose-internals",
            runtime.dshEntrypoint.path,
            "web",
            "--port",
            "0",
        ])
        XCTAssertEqual(launch.environment["PATH"], "")
        XCTAssertEqual(launch.environment["DSH_HOME"], runtime.homeDirectory.path)
        XCTAssertFalse(launch.arguments.contains("node"))
        XCTAssertFalse(launch.arguments.contains("dsh"))
    }
}
