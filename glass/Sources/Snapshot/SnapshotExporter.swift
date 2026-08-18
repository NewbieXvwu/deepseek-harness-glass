import AppKit
import SwiftUI

/// 在 CI 中使用确定性的离屏 AppKit 位图生成原生 UI 快照。
/// 它验证 SwiftUI 布局和官方 token 映射；系统真实折射效果仍由运行中的 macOS 窗口验收。
enum SnapshotExporter {
    enum SnapshotError: Error, LocalizedError {
        case cannotCreateBitmap
        case cannotEncodePNG

        var errorDescription: String? {
            switch self {
            case .cannotCreateBitmap:
                return "Unable to create the snapshot bitmap."
            case .cannotEncodePNG:
                return "Unable to encode the snapshot PNG."
            }
        }
    }

    @MainActor
    static func exportIfRequested() throws -> Bool {
        guard let outputPath = ProcessInfo.processInfo.environment["DSH_GLASS_SNAPSHOT_PATH"], !outputPath.isEmpty else {
            return false
        }

        let mode: NativeAppShell.PresentationMode
        switch ProcessInfo.processInfo.environment["DSH_GLASS_SNAPSHOT_MODE"] {
        case "conversation":
            mode = .conversation
        case "tooling":
            mode = .tooling
        case "approval":
            mode = .approval
        case "question":
            mode = .question
        default:
            mode = .welcome
        }
        let sessionStore = NativeSessionStore()
        let workspaceStore = NativeWorkspaceStore()
        switch mode {
        case .tooling:
            sessionStore.loadSnapshotToolingFixture()
        case .approval:
            sessionStore.loadSnapshotApprovalFixture()
            workspaceStore.loadSnapshotFixtureWorkspace()
        case .question:
            sessionStore.loadSnapshotQuestionFixture()
            workspaceStore.loadSnapshotFixtureWorkspace()
        case .welcome, .conversation:
            break
        }
        let presentation = NativeShellPresentation(
            mode: mode,
            workspaceStore: workspaceStore,
            sessionStore: sessionStore
        )
        let shellController = NativeShellController(presentation: presentation)
        let size = snapshotSize(environment: ProcessInfo.processInfo.environment)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = shellController
        window.contentView?.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        shellController.refreshForCurrentViewport()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let hostedView = window.contentView,
              let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotError.cannotCreateBitmap
        }

        bitmap.size = size
        hostedView.cacheDisplay(in: hostedView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.cannotEncodePNG
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: outputURL, options: .atomic)
        window.orderOut(nil)
        return true
    }

    /// A paired review may match an official browser's CSS viewport exactly.
    /// Invalid or omitted values preserve the established 1280×840 CI baseline.
    private static func snapshotSize(environment: [String: String]) -> NSSize {
        let defaultSize = NSSize(width: 1280, height: 840)
        guard let widthText = environment["DSH_GLASS_SNAPSHOT_WIDTH"],
              let heightText = environment["DSH_GLASS_SNAPSHOT_HEIGHT"],
              let width = Double(widthText),
              let height = Double(heightText),
              width.isFinite, height.isFinite,
              width >= 1, height >= 1,
              width <= 4096, height <= 4096
        else { return defaultSize }
        return NSSize(width: width, height: height)
    }
}
