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
        .library(name: "GlassPluginPlane", targets: ["GlassPluginPlane"]),
        .executable(name: "DeepSeekHarnessGlassApp", targets: ["DeepSeekHarnessGlassApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
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
            dependencies: ["GlassSpec", "GlassPortableCore"],
            path: "Sources/Core",
            resources: [.process("Resources")],
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassUI",
            dependencies: [
                "GlassCore",
                "GlassSpec",
                "GlassPortableCore",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/UI",
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "GlassSnapshot",
            dependencies: ["GlassCore", "GlassSpec", "GlassUI"],
            path: "Sources/Snapshot",
            swiftSettings: [.define("DEEPSEEK_HARNESS_PACKAGE"), .unsafeFlags(["-enable-testing"])]
        ),
        // The only target permitted to import/use WebKit for the registered
        // Ghost Plane. Core/UI/App do not depend on it.
        .target(
            name: "GlassPluginPlane",
            dependencies: ["GlassCore", "GlassSpec"],
            path: "Sources/PluginPlane",
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
            dependencies: ["GlassCore", "GlassSpec", "GlassPortableCore"],
            path: "Tests/Core"
        ),
        .testTarget(
            name: "GlassAppTests",
            dependencies: ["DeepSeekHarnessGlassApp", "GlassCore", "GlassPortableCore", "GlassSpec", "GlassUI"],
            path: "Tests/App"
        ),
        .testTarget(
            name: "GlassSnapshotTests",
            dependencies: ["GlassSnapshot"],
            path: "Tests/Snapshot"
        ),
        .testTarget(
            name: "GlassPluginPlaneTests",
            dependencies: ["GlassPluginPlane", "GlassCore", "GlassSpec"],
            path: "Tests/PluginPlane"
        ),
    ]
)
