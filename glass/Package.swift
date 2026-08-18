// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepSeekHarnessGlassModules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GlassSpec", targets: ["GlassSpec"]),
        .library(name: "GlassCore", targets: ["GlassCore"]),
        .library(name: "GlassUI", targets: ["GlassUI"]),
        .library(name: "GlassSnapshot", targets: ["GlassSnapshot"]),
        .executable(name: "DeepSeekHarnessGlassApp", targets: ["DeepSeekHarnessGlassApp"]),
    ],
    targets: [
        .target(
            name: "GlassSpec",
            path: "Sources/Spec",
            resources: [.process("Fixtures")],
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassCore",
            dependencies: ["GlassSpec"],
            path: "Sources/Core",
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassUI",
            dependencies: ["GlassCore", "GlassSpec"],
            path: "Sources/UI",
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassSnapshot",
            dependencies: ["GlassCore", "GlassSpec", "GlassUI"],
            path: "Sources/Snapshot",
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "DeepSeekHarnessGlassApp",
            dependencies: ["GlassCore", "GlassSpec", "GlassUI", "GlassSnapshot"],
            path: "Sources/App",
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .testTarget(
            name: "GlassSpecTests",
            dependencies: ["GlassSpec"],
            path: "Tests/Spec"
        ),
        .testTarget(
            name: "GlassCoreTests",
            dependencies: ["GlassCore", "GlassSpec"],
            path: "Tests/Core"
        ),
    ]
)
