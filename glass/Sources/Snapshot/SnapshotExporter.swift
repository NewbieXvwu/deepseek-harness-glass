import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI
#endif
/// Captures on-screen native UI snapshots in CI through ScreenCaptureKit.
/// The capture samples the real WindowServer composition, including AppKit
/// sidebar/inspector materials; a degraded or black frame fails the export.
/// A window that keeps the exact size the snapshot asks for.
///
/// `NSWindow` constrains any titled window to the screen's visible frame, so
/// the menu bar and Dock silently shorten a tall snapshot: a 1280x1100 request
/// became 1280x1091 on a 1600x1200 display. The captured viewport must equal
/// the baseline viewport, so this override opts out of that constraint.
private final class SnapshotWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

enum SnapshotExporter {
    enum SnapshotError: Error, LocalizedError {
        case cannotEncodePNG
        case viewportClamped(requested: NSSize, actual: NSSize, display: NSSize)
        case compositorUnavailable
        case blackFrame
        case titlebarInsetUnavailable

        var errorDescription: String? {
            switch self {
            case .cannotEncodePNG:
                return "Unable to encode the snapshot PNG."
            case let .viewportClamped(requested, actual, display):
                return """
                Snapshot viewport was clamped by the display: requested \
                \(Int(requested.width))x\(Int(requested.height)), got \
                \(Int(actual.width))x\(Int(actual.height)) on a \
                \(Int(display.width))x\(Int(display.height)) display. The column \
                layout resolves against the clamped width, so the capture would \
                not be the baseline layout. Widen the display mode before capturing.
                """
            case .compositorUnavailable:
                return "ScreenCaptureKit could not capture the snapshot window."
            case .blackFrame:
                return "The compositor returned an all-black frame."
            case .titlebarInsetUnavailable:
                return "Could not determine the titlebar safe-area inset to crop."
            }
        }
    }

    static func lockedAppearanceName(snapshotColorScheme: String?) -> NSAppearance.Name {
        snapshotColorScheme == "dark" ? .darkAqua : .aqua
    }

    static func viewportMatches(requested: NSSize, actual: NSSize) -> Bool {
        abs(actual.width - requested.width) <= 1 && abs(actual.height - requested.height) <= 1
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
        case "conversation", "jobs", "todo", "goal":
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
        case .conversation where requestedMode == "jobs":
            sessionStore.loadSnapshotJobsFixture()
            workspaceStore.loadSnapshotJobsFixtureWorkspace()
        case .conversation where requestedMode == "todo":
            sessionStore.loadSnapshotTodoFixture()
            workspaceStore.loadSnapshotFixtureWorkspace()
        case .conversation where requestedMode == "goal":
            sessionStore.loadSnapshotGoalFixture()
            workspaceStore.loadSnapshotFixtureWorkspace()
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
        let appearanceName = lockedAppearanceName(
            snapshotColorScheme: ProcessInfo.processInfo.environment["DSH_GLASS_SNAPSHOT_COLOR_SCHEME"]
        )
        // System split-item materials resolve from the application effective
        // appearance, not only the borderless bitmap context. Set it before
        // creating SwiftUI hosting views so a locked light/dark capture is
        // truly paired with the official scene.
        NSApp.appearance = NSAppearance(named: appearanceName)
        let presentation = NativeShellPresentation(
            mode: mode,
            workspaceStore: workspaceStore,
            sessionStore: sessionStore,
            workspaceSnapshotDialog: workspaceSnapshotDialog,
            jobsPopoverInitiallyOpen: requestedMode == "jobs",
            // The official capture contract fixes Jobs to en-US. This affects
            // only the snapshot view's controlled locale lookup, never Host
            // state or normal application language selection.
            jobsSnapshotLanguageCode: requestedMode == "jobs" ? "en" : nil
        )
        let shellController = NativeShellRootController(presentation: presentation)
        let size = snapshotSize(environment: ProcessInfo.processInfo.environment)
        // Snapshot the same native titlebar/material composition used by the
        // running App. A borderless off-screen window does not host AppKit's
        // sidebar/inspector materials and rendered transparent structure as
        // black, which is not a valid production appearance.
        let window = SnapshotWindow(
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
        // WindowServer may not have propagated the window appearance to child
        // controllers yet. Pin the snapshot root explicitly; the running
        // application never uses this snapshot-only override.
        shellController.view.appearance = NSAppearance(named: appearanceName)
        window.contentView?.appearance = NSAppearance(named: appearanceName)
        // Assigning contentViewController makes AppKit resize the window to the
        // controller's fitting size. The shell root has no intrinsic size, so
        // the window collapsed to 1x1 and every capture sampled a degenerate
        // window. Setting contentView.frame alone does not resize the window;
        // the window itself must be sized after the controller is installed.
        // The official WebUI baseline has no titlebar, but a `.titled` window
        // insets its content by the titlebar safe area: measured against the
        // baseline, top-anchored elements sat 40px low while bottom-anchored
        // ones stayed put. That is a shorter usable height, not a translation,
        // so cropping alone would misplace bottom-anchored content.
        //
        // Instead grow the window by the inset so the safe area measures
        // exactly the requested viewport, then crop the titlebar band off the
        // capture. Both top- and bottom-anchored content then match, and the
        // exported PNG is still exactly `size`.
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        let titlebarInset = window.contentView?.safeAreaInsets.top ?? 0
        let captureSize = NSSize(width: size.width, height: size.height + titlebarInset)
        window.setContentSize(captureSize)
        window.contentView?.frame = NSRect(origin: .zero, size: captureSize)
        // Place the window explicitly; `center()` would re-apply the visible
        // frame constraint this window deliberately opts out of.
        if let screen = NSScreen.main {
            let frame = window.frame
            window.setFrameOrigin(NSPoint(
                x: screen.frame.minX + max(0, (screen.frame.width - frame.width) / 2),
                y: screen.frame.maxY - frame.height
            ))
        }
        window.orderFrontRegardless()
        // AppKit silently shrinks a window that exceeds the display. On the
        // 1024x768 hosted runner a 1280x840 request became 1024 wide, and
        // OfficialColumnLayout.resolve then took its details-dropped branch,
        // so the capture was a two-column shell compared against a
        // three-column baseline. Refuse to export a mislaid viewport.
        let actualContentSize = window.contentRect(forFrameRect: window.frame).size
        if !viewportMatches(requested: captureSize, actual: actualContentSize) {
            throw SnapshotError.viewportClamped(
                requested: captureSize,
                actual: actualContentSize,
                display: NSScreen.main?.frame.size ?? .zero
            )
        }
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        shellController.refreshForCurrentViewport()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        // A SwiftUI/AppKit refresh may update a fitting-size constraint after
        // the first sizing pass. Re-assert the requested content viewport
        // before asking WindowServer to capture; accepting a wider source then
        // cropping/rescaling it would invalidate the same-state evidence.
        window.setContentSize(captureSize)
        window.contentView?.frame = NSRect(origin: .zero, size: captureSize)
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        let finalContentSize = window.contentRect(forFrameRect: window.frame).size
        if !viewportMatches(requested: captureSize, actual: finalContentSize) {
            throw SnapshotError.viewportClamped(
                requested: captureSize,
                actual: finalContentSize,
                display: NSScreen.main?.frame.size ?? .zero
            )
        }
        window.displayIfNeeded()

        // macOS 26 replaces the obsolete CGWindowList image APIs with this
        // supported single-frame ScreenCaptureKit compositor path. Measured on
        // a macos-26 hosted runner, it returns fully composited system
        // materials (sidebar and inspector bands both >99% non-black), so a
        // black frame here means a real defect rather than a platform limit.
        let configuration = SCScreenshotConfiguration()
        configuration.width = Int(captureSize.width)
        configuration.height = Int(captureSize.height)
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
            candidate.size = captureSize
            compositorBitmap = hasVisibleSDRContent(candidate) ? candidate : nil
        } else {
            compositorBitmap = nil
        }
        // A degraded capture used to fall back to `cacheDisplay`, which by
        // Apple's own account cannot render materials or blurs. That fallback
        // turned every capture failure into a passing run with a wrong image,
        // so the pipeline reported success while producing invalid evidence.
        // Fail instead: an unusable compositor is a CI defect, not a variant.
        let bitmap: NSBitmapImageRep
        if let compositorBitmap {
            bitmap = compositorBitmap
            FileHandle.standardError.write(Data("snapshot capture: current-process ScreenCaptureKit compositor frame accepted\n".utf8))
        } else if let systemBitmap = systemWindowBitmap(windowID: CGWindowID(window.windowNumber), size: captureSize) {
            bitmap = systemBitmap
            FileHandle.standardError.write(Data("snapshot capture: system screencapture window compositor frame accepted\n".utf8))
        } else if shareableWindow == nil {
            throw SnapshotError.compositorUnavailable
        } else {
            throw SnapshotError.blackFrame
        }
        let exported = try cropTitlebar(from: bitmap, inset: titlebarInset, outputSize: size)
        guard let png = exported.representation(using: .png, properties: [:]) else {
            throw SnapshotError.cannotEncodePNG
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: outputURL, options: .atomic)
        window.orderOut(nil)
        return true
    }

    /// Removes the titlebar band so the exported frame matches the official
    /// WebUI baseline, which has no titlebar. The window was grown by exactly
    /// this inset beforehand, so the remaining pixels are the requested
    /// viewport with its layout anchored the same way as the baseline.
    @MainActor
    private static func cropTitlebar(
        from bitmap: NSBitmapImageRep,
        inset: CGFloat,
        outputSize: NSSize
    ) throws -> NSBitmapImageRep {
        guard inset > 0 else { return bitmap }
        guard let source = bitmap.cgImage else { throw SnapshotError.titlebarInsetUnavailable }
        // Work in pixels: a Retina capture has more pixels than points.
        let scale = CGFloat(source.height) / (outputSize.height + inset)
        let insetPixels = (inset * scale).rounded()
        let cropped = CGRect(
            x: 0,
            y: insetPixels,
            width: CGFloat(source.width),
            height: CGFloat(source.height) - insetPixels
        )
        guard let image = source.cropping(to: cropped) else {
            throw SnapshotError.titlebarInsetUnavailable
        }
        let result = NSBitmapImageRep(cgImage: image)
        result.size = outputSize
        return result
    }

    /// Uses macOS's own window screenshot service only for the CI review
    /// exporter. The running UI neither invokes a subprocess nor depends on
    /// this path; it exists so a headless runner can still inspect actual
    /// WindowServer material after ScreenCaptureKit returns a black frame.
    @MainActor
    private static func systemWindowBitmap(windowID: CGWindowID, size: NSSize) -> NSBitmapImageRep? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deepseek-harness-glass-window-\(windowID)-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(windowID)", temporaryURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let image = NSImage(contentsOf: temporaryURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = size
        return hasVisibleSDRContent(bitmap) ? bitmap : nil
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
