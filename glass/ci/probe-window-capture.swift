// Temporary diagnostic probe (not shipped).
//
// Reproduces the SnapshotExporter window/material setup and isolates which
// factor makes SCScreenshotManager return an all-black frame on the hosted
// macOS-26 runner. Each variant prints a non-black ratio so the failing
// variable is identified by measurement rather than inference.

import AppKit
import CoreGraphics
import ScreenCaptureKit

func nonBlackRatio(_ cg: CGImage) -> Double {
    let w = cg.width, h = cg.height
    guard w > 0, h > 0 else { return 0 }
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 0 }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var lit = 0
    for i in stride(from: 0, to: buf.count, by: 4) {
        if buf[i] > 8 || buf[i + 1] > 8 || buf[i + 2] > 8 { lit += 1 }
    }
    return Double(lit) / Double(w * h)
}

func spinRunLoop(seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        if let e = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) {
            NSApp.sendEvent(e)
        }
    }
}

/// Builds a sidebar+inspector split exactly like NativeSplitContainer so the
/// probe exercises real AppKit system materials, not a plain colored view.
func makeSplit() -> NSSplitViewController {
    func pane(_ color: NSColor) -> NSViewController {
        let vc = NSViewController()
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = color.cgColor
        vc.view = v
        return vc
    }
    let split = NSSplitViewController()
    let sidebar = NSSplitViewItem(sidebarWithViewController: NSViewController().then {
        $0.view = NSView()   // transparent host: system owns the material
    })
    let center = NSSplitViewItem(viewController: pane(.white))
    let inspector = NSSplitViewItem(inspectorWithViewController: NSViewController().then {
        $0.view = NSView()
    })
    split.addSplitViewItem(sidebar)
    split.addSplitViewItem(center)
    split.addSplitViewItem(inspector)
    return split
}

extension NSObject {
    func then(_ body: (Self) -> Void) -> Self { body(self); return self }
}

@MainActor
func capture(window: NSWindow, label: String) async {
    guard let content = try? await SCShareableContent.currentProcess,
          let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
    else {
        print("\(label): NO SHAREABLE WINDOW (windowNumber=\(window.windowNumber))")
        return
    }
    let cfg = SCScreenshotConfiguration()
    cfg.width = Int(window.frame.width)
    cfg.height = Int(window.frame.height)
    cfg.showsCursor = false
    cfg.ignoreShadows = true
    do {
        let shot = try await SCScreenshotManager.captureScreenshot(
            contentFilter: SCContentFilter(desktopIndependentWindow: target),
            configuration: cfg
        )
        if let img = shot.sdrImage {
            let r = nonBlackRatio(img)
            print(String(format: "%@: %dx%d nonblack=%.6f => %@",
                         label, img.width, img.height, r,
                         r > 0.01 ? "REAL CONTENT" : "ALL BLACK"))
        } else {
            print("\(label): sdrImage == nil")
        }
    } catch {
        print("\(label): THREW \(error)")
    }
}

@MainActor
func runVariant(name: String, size: NSSize, activate: Bool, settle: Double) async {
    let win = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false
    )
    win.titleVisibility = .hidden
    win.titlebarAppearsTransparent = true
    win.appearance = NSAppearance(named: .aqua)
    win.isReleasedWhenClosed = false
    win.contentViewController = makeSplit()
    if activate {
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    } else {
        win.orderFrontRegardless()
    }
    win.contentView?.layoutSubtreeIfNeeded()
    win.displayIfNeeded()
    if settle > 0 { spinRunLoop(seconds: settle) }

    let onScreen = win.isVisible
    let scr = NSScreen.main?.frame ?? .zero
    print("--- \(name) | size=\(Int(size.width))x\(Int(size.height)) activate=\(activate) settle=\(settle)s visible=\(onScreen) screen=\(Int(scr.width))x\(Int(scr.height))")
    await capture(window: win, label: "    \(name)")
    win.orderOut(nil)
}

@main
struct Probe {
    @MainActor
    static func main() async {
        NSApplication.shared.setActivationPolicy(.regular)
        print("=== screens ===")
        for s in NSScreen.screens { print("  \(Int(s.frame.width))x\(Int(s.frame.height)) scale=\(s.backingScaleFactor)") }
        print("preflight=\(CGPreflightScreenCaptureAccess())")

        // V1 reproduces the current exporter exactly (oversized window, no settle).
        await runVariant(name: "V1-current-1280x840-nosettle", size: NSSize(width: 1280, height: 840), activate: false, settle: 0)
        // V2 isolates the compositing race only.
        await runVariant(name: "V2-1280x840-settle1.5", size: NSSize(width: 1280, height: 840), activate: false, settle: 1.5)
        // V3 isolates activation + key window.
        await runVariant(name: "V3-1280x840-activate-settle1.5", size: NSSize(width: 1280, height: 840), activate: true, settle: 1.5)
        // V4 isolates the window-exceeds-display factor.
        await runVariant(name: "V4-fits-1000x700-activate-settle1.5", size: NSSize(width: 1000, height: 700), activate: true, settle: 1.5)
    }
}
