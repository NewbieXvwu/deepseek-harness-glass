import AppKit
import CoreGraphics
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
    static func exportIfRequested() throws -> Bool {
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

        let bitmap: NSBitmapImageRep
        if let composited = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            // The WindowServer path includes system-owned sidebar and inspector
            // material. `cacheDisplay` below is only a deterministic fallback
            // for environments where a window image is unavailable.
            bitmap = NSBitmapImageRep(cgImage: composited)
        } else if let hostedView = window.contentView,
                  let fallback = NSBitmapImageRep(
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
                  ) {
            fallback.size = size
            hostedView.cacheDisplay(in: hostedView.bounds, to: fallback)
            bitmap = fallback
        } else {
            throw SnapshotError.cannotCreateBitmap
        }

        bitmap.size = size
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
