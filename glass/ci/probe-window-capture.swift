// Temporary diagnostic probe (not shipped).
//
// Probe v1 proved SCScreenshotManager returns real pixels on this runner, but
// its window collapsed to 418x50 because empty split items carry no intrinsic
// size. v2 pins the window frame after installing the controller and measures
// the sidebar band specifically, which is the region T5.3 reported as black.

import AppKit
import CoreGraphics
import ScreenCaptureKit

struct Stats { let w: Int, h: Int, nonBlack: Double }

func analyze(_ cg: CGImage, band: ClosedRange<Double>? = nil) -> Stats {
    let w = cg.width, h = cg.height
    guard w > 0, h > 0 else { return Stats(w: 0, h: 0, nonBlack: 0) }
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return Stats(w: w, h: h, nonBlack: 0) }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let x0 = Int((band?.lowerBound ?? 0) * Double(w))
    let x1 = Int((band?.upperBound ?? 1) * Double(w))
    var lit = 0, total = 0
    for y in 0..<h {
        for x in x0..<max(x0 + 1, min(x1, w)) {
            let i = (y * w + x) * 4
            total += 1
            if buf[i] > 8 || buf[i + 1] > 8 || buf[i + 2] > 8 { lit += 1 }
        }
    }
    return Stats(w: w, h: h, nonBlack: total > 0 ? Double(lit) / Double(total) : 0)
}

func spin(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        while let e = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) {
            NSApp.sendEvent(e)
        }
    }
}

final class Filled: NSViewController {
    let color: NSColor?
    init(color: NSColor?) { self.color = color; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        let v = NSView()
        if let color {
            v.wantsLayer = true
            v.layer?.backgroundColor = color.cgColor
        }
        // A label proves content-layer drawing survives the capture.
        let t = NSTextField(labelWithString: "CONTENT")
        t.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(t)
        NSLayoutConstraint.activate([
            t.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            t.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        view = v
    }
}

@MainActor
func capture(_ win: NSWindow, _ label: String) async {
    guard let c = try? await SCShareableContent.currentProcess,
          let target = c.windows.first(where: { $0.windowID == CGWindowID(win.windowNumber) })
    else { print("  \(label): NO SHAREABLE WINDOW"); return }

    let cfg = SCScreenshotConfiguration()
    cfg.width = Int(win.frame.width)
    cfg.height = Int(win.frame.height)
    cfg.showsCursor = false
    cfg.ignoreShadows = true
    do {
        let shot = try await SCScreenshotManager.captureScreenshot(
            contentFilter: SCContentFilter(desktopIndependentWindow: target),
            configuration: cfg)
        guard let img = shot.sdrImage else { print("  \(label): sdrImage nil"); return }
        let all = analyze(img)
        // sidebar = leftmost 280/1280 = 0.219 ; inspector = rightmost 360/1280
        let side = analyze(img, band: 0.0...0.21)
        let insp = analyze(img, band: 0.72...1.0)
        print(String(format: "  %@: %dx%d all=%.4f SIDEBAR=%.4f[%@] INSPECTOR=%.4f[%@]",
                     label, all.w, all.h, all.nonBlack,
                     side.nonBlack, side.nonBlack > 0.01 ? "OK" : "BLACK",
                     insp.nonBlack, insp.nonBlack > 0.01 ? "OK" : "BLACK"))
    } catch { print("  \(label): THREW \(error)") }
}

@MainActor
func variant(_ name: String, size: NSSize, settle: Double, activate: Bool) async {
    let split = NSSplitViewController()
    split.addSplitViewItem(NSSplitViewItem(sidebarWithViewController: Filled(color: nil)))
    split.addSplitViewItem(NSSplitViewItem(viewController: Filled(color: .white)))
    split.addSplitViewItem(NSSplitViewItem(inspectorWithViewController: Filled(color: nil)))

    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                       styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                       backing: .buffered, defer: false)
    win.titleVisibility = .hidden
    win.titlebarAppearsTransparent = true
    win.appearance = NSAppearance(named: .aqua)
    win.isReleasedWhenClosed = false
    win.contentViewController = split
    // Pin the frame AFTER the controller is installed: a split controller's
    // preferred size otherwise shrinks the window (probe v1 got 418x50).
    win.setContentSize(size)
    win.setFrame(NSRect(origin: win.frame.origin, size: win.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size),
                 display: true)
    if activate { win.center(); win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    else { win.orderFrontRegardless() }
    win.contentView?.layoutSubtreeIfNeeded()
    win.displayIfNeeded()
    if settle > 0 { spin(settle) }
    print("--- \(name) frame=\(Int(win.frame.width))x\(Int(win.frame.height)) visible=\(win.isVisible)")
    await capture(win, name)
    win.orderOut(nil)
}

@main
struct Probe {
    @MainActor
    static func main() async {
        NSApplication.shared.setActivationPolicy(.regular)
        for s in NSScreen.screens { print("screen \(Int(s.frame.width))x\(Int(s.frame.height)) scale=\(s.backingScaleFactor)") }
        print("preflight=\(CGPreflightScreenCaptureAccess())")
        await variant("A-1280x840-nosettle",   size: NSSize(width: 1280, height: 840), settle: 0,   activate: false)
        await variant("B-1280x840-settle1.5",  size: NSSize(width: 1280, height: 840), settle: 1.5, activate: false)
        await variant("C-1280x840-act-settle", size: NSSize(width: 1280, height: 840), settle: 1.5, activate: true)
        await variant("D-1000x700-act-settle", size: NSSize(width: 1000, height: 700), settle: 1.5, activate: true)
    }
}
