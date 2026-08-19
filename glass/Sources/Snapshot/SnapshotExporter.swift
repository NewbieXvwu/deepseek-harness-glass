import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI
#endif
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
    static func exportIfRequested() async throws -> Bool {
        guard let outputPath = ProcessInfo.processInfo.environment["DSH_GLASS_SNAPSHOT_PATH"], !outputPath.isEmpty else {
            return false
        }

        let requestedMode = ProcessInfo.processInfo.environment["DSH_GLASS_SNAPSHOT_MODE"]
        let mode: NativeAppShell.PresentationMode
        let workspaceSnapshotDialog: WorkspaceBrowserView.SnapshotDialog
        switch requestedMode {
        case "conversation":
            mode = .conversation
        case "workspace-search", "workspace-rename", "session-rename", "workspace-delete":
            mode = .welcome
        case "tooling":
            mode = .tooling
        case "approval":
            mode = .approval
        case "question":
            mode = .question
        default:
            mode = .welcome
        }
        switch requestedMode {
        case "workspace-rename":
            workspaceSnapshotDialog = .workspaceRename
        case "session-rename":
            workspaceSnapshotDialog = .sessionRename
        case "workspace-delete":
            workspaceSnapshotDialog = .workspaceDelete
        default:
            workspaceSnapshotDialog = .none
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
        case .welcome where requestedMode == "workspace-search":
            workspaceStore.loadSnapshotFixtureSearch()
        case .welcome where requestedMode == "workspace-rename"
            || requestedMode == "session-rename"
            || requestedMode == "workspace-delete":
            workspaceStore.loadSnapshotFixtureWorkspaceWelcome()
        case .welcome, .conversation:
            break
        }
        let appearanceName: NSAppearance.Name = ProcessInfo.processInfo.environment["DSH_GLASS_SNAPSHOT_COLOR_SCHEME"] == "dark"
            ? .darkAqua
            : .aqua
        // System split-item materials resolve from the application effective
        // appearance, not only the borderless bitmap context. Set it before
        // creating SwiftUI hosting views so a locked light/dark capture is
        // truly paired with the official scene.
        NSApp.appearance = NSAppearance(named: appearanceName)
        let presentation = NativeShellPresentation(
            mode: mode,
            workspaceStore: workspaceStore,
            sessionStore: sessionStore,
            workspaceSnapshotDialog: workspaceSnapshotDialog
        )
        let shellController = NativeShellRootController(presentation: presentation)
        let size = snapshotSize(environment: ProcessInfo.processInfo.environment)
        // Snapshot the same native titlebar/material composition used by the
        // running App. A borderless off-screen window does not host AppKit's
        // sidebar/inspector materials and rendered transparent structure as
        // black, which is not a valid production appearance.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: appearanceName)
        window.isReleasedWhenClosed = false
        window.contentViewController = shellController
        // `cacheDisplay` may run before WindowServer has propagated the window
        // appearance to child controllers. Pin the off-screen root explicitly;
        // the running application never uses this snapshot-only override.
        shellController.view.appearance = NSAppearance(named: appearanceName)
        window.contentView?.appearance = NSAppearance(named: appearanceName)
        window.contentView?.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        shellController.refreshForCurrentViewport()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // `cacheDisplay` cannot render WindowServer-owned materials. macOS 26
        // replaces the obsolete CGWindowList image APIs with this supported
        // single-frame ScreenCaptureKit compositor path. GitHub's headless
        // runner can nevertheless return an all-black, non-error SDR frame
        // when its WindowServer denies compositing. Such a frame is invalid
        // evidence, so retain an explicit deterministic AppKit fallback for
        // layout review rather than exporting a false black visual result.
        let configuration = SCScreenshotConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.displayIntent = .local
        // A window filter captures the actual WindowServer composition of this
        // process, including AppKit-owned sidebar/inspector material, without
        // sampling unrelated or inaccessible headless display pixels.
        let currentProcessContent = try? await SCShareableContent.currentProcess
        let shareableWindow = currentProcessContent?.windows.first {
            $0.windowID == CGWindowID(window.windowNumber)
        }
        let compositorBitmap: NSBitmapImageRep?
        if let shareableWindow,
           let screenshot = try? await SCScreenshotManager.captureScreenshot(
            contentFilter: SCContentFilter(desktopIndependentWindow: shareableWindow),
            configuration: configuration
           ), let composited = screenshot.sdrImage {
            let candidate = NSBitmapImageRep(cgImage: composited)
            candidate.size = size
            compositorBitmap = hasVisibleSDRContent(candidate) ? candidate : nil
        } else {
            compositorBitmap = nil
        }
        let bitmap: NSBitmapImageRep
        if let compositorBitmap {
            bitmap = compositorBitmap
            FileHandle.standardError.write(Data("snapshot capture: current-process ScreenCaptureKit compositor frame accepted\n".utf8))
        } else {
            bitmap = try fallbackBitmap(from: window, size: size)
            FileHandle.standardError.write(Data("snapshot capture: ScreenCaptureKit compositor frame unavailable or black; using deterministic AppKit fallback\n".utf8))
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.cannotEncodePNG
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: outputURL, options: .atomic)
        window.orderOut(nil)
        return true
    }

    @MainActor
    private static func fallbackBitmap(from window: NSWindow, size: NSSize) throws -> NSBitmapImageRep {
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
              )
        else {
            throw SnapshotError.cannotCreateBitmap
        }
        bitmap.size = size
        hostedView.cacheDisplay(in: hostedView.bounds, to: bitmap)
        return bitmap
    }

    /// The macOS 26 screenshot API can return an all-black CGImage without an
    /// error when a noninteractive WindowServer doesn't grant compositing.
    /// Do not treat that transport artifact as a native visual snapshot.
    @MainActor
    static func hasVisibleSDRContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard let data = bitmap.bitmapData,
              bitmap.bitsPerPixel >= 24,
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0
        else { return false }
        let horizontalStep = max(1, bitmap.pixelsWide / 24)
        let verticalStep = max(1, bitmap.pixelsHigh / 24)
        let bytesPerPixel = bitmap.bitsPerPixel / 8
        let colorOffset = bitmap.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        guard bytesPerPixel >= colorOffset + 3 else { return false }
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: verticalStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: horizontalStep) {
                let offset = y * bitmap.bytesPerRow + x * bytesPerPixel + colorOffset
                if data[offset] > 8 || data[offset + 1] > 8 || data[offset + 2] > 8 {
                    return true
                }
            }
        }
        return false
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
