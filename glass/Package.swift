// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepSeekHarnessGlassModules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GlassSpec", targets: ["GlassSpec"]),
        .library(name: "GlassPortableCore", targets: ["GlassPortableCore"]),
        .library(name: "GlassCore", targets: ["GlassCore"]),
        .library(name: "GlassUI", targets: ["GlassUI"]),
        .library(name: "GlassSnapshot", targets: ["GlassSnapshot"]),
        .executable(name: "DeepSeekHarnessGlassApp", targets: ["DeepSeekHarnessGlassApp"]),
    ],
    targets: [
        .target(
            name: "GlassSpec",
            path: "Sources/Spec",
            resources: [.process("Fixtures"), .process("Locales")],
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassPortableCore",
            path: "Sources/PortableCore",
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassCore",
            dependencies: ["GlassSpec"],
            path: "Sources/Core",
            resources: [.process("Resources")],
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassUI",
            dependencies: ["GlassCore", "GlassSpec", "GlassPortableCore"],
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
            name: "GlassPortableCoreTests",
            dependencies: ["GlassPortableCore"],
            path: "Tests/PortableCore"
        ),
        .testTarget(
            name: "GlassCoreTests",
            dependencies: ["GlassCore", "GlassSpec"],
            path: "Tests/Core"
        ),
        .testTarget(
            name: "GlassAppTests",
            dependencies: ["DeepSeekHarnessGlassApp", "GlassCore", "GlassSpec", "GlassUI"],
            path: "Tests/App"
        ),
        .testTarget(
            name: "GlassSnapshotTests",
            dependencies: ["GlassSnapshot"],
            path: "Tests/Snapshot"
        ),
    ]
)
