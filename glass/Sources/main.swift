// DeepSeek Harness — 原生 SwiftUI 液态玻璃壳
//
// 架构与 Electron 壳完全一致，但玻璃效果使用苹果公开 API：
//   - 窗口级玻璃：.containerBackground(.glass, for: .window)（macOS 26+，
//     苹果自家应用同款，含边缘折射/散射）
//   - 透明 WKWebView 加载 dsh 前端，注入 GLASS_CSS 把设计令牌改为半透明
//   - 内置 Node + dsh 后端引擎（从 Electron 版的 node_modules 复用），
//     spawn `dsh web --port 0`，解析 stdout 拿到端口后加载
//   - DSH_HOME 默认 ~/.dsh，与 CLI 共享凭据/会话/配置
//
// 编译：swiftc -O -parse-as-library -target arm64-apple-macosx26.0 Sources/main.swift

import SwiftUI
import WebKit
import AppKit

// MARK: - 玻璃 CSS（与 Electron 版同款，注入到 dsh 前端）

let GLASS_CSS = """
html, body, #root { background: transparent !important; }
html { color-scheme: light !important; }
html, body { -webkit-font-smoothing: antialiased !important; }
/* 极淡衬底：给文字一个近实底，阻断玻璃背后颜色渗进字形（4% 几乎不可见） */
body::before {
  content: "";
  position: fixed;
  inset: 0;
  background: rgba(255, 255, 255, 0.005);
  z-index: -1;
  pointer-events: none;
}
body[data-ds-dark-theme] {
  --dsw-alias-bg-base: rgba(18, 19, 23, 0.03) !important;
  --dsw-alias-bg-layer-1: rgba(28, 29, 34, 0.03) !important;
  --dsw-alias-bg-layer-2: rgba(36, 37, 43, 0.03) !important;
  --dsw-alias-bg-layer-3: rgba(44, 45, 52, 0.03) !important;
  --dsw-alias-bg-module-platform: rgba(13, 14, 18, 0.03) !important;
  --dsw-alias-bg-overlay: rgba(44, 45, 52, 0.70) !important;
  --dsw-alias-bg-multi-select: rgba(33, 34, 40, 0.03) !important;
  --dsw-alias-toast-bg: rgba(60, 60, 61, 0.92) !important;
  --dsw-alias-tooltip-bg: rgba(33, 33, 35, 0.94) !important;
  --dsw-specific-sidebar-fill: rgba(22, 23, 28, 0.03) !important;
  --dsw-specific-menu: rgba(38, 39, 46, 0.60) !important;
  --dsw-specific-selector: rgba(34, 35, 41, 0.55) !important;
  --dsw-specific-tip: rgba(36, 37, 43, 0.50) !important;
  --dsw-specific-input-major: rgba(28, 29, 34, 0.45) !important;
  --dsw-specific-login-input: rgba(30, 31, 37, 0.50) !important;
  --dsw-specific-bubble: rgba(30, 31, 36, 0.03) !important;
  --dsw-specific-bubble-highlight: rgba(30, 31, 36, 0.03) !important;
  --dsw-hovercard-bg: rgba(38, 39, 46, 0.65) !important;
  --dsw-alias-markdown-code-block: rgba(26, 27, 32, 0.03) !important;
  --dsw-alias-markdown-code-block-banner: rgba(30, 31, 36, 0.03) !important;
  --dsw-alias-label-primary: rgb(240, 242, 245) !important;
  --dsw-alias-label-primary-dimmed: rgb(225, 229, 238) !important;
  --dsw-alias-label-primary-bluish: rgb(147, 197, 253) !important;
  --dsw-alias-label-secondary: rgb(207, 211, 214) !important;
  --dsw-alias-label-tertiary: rgb(173, 178, 184) !important;
  --dsw-alias-label-caption: rgb(151, 157, 166) !important;
  --dsw-alias-label-dimmed: rgb(127, 130, 135) !important;
  --dsw-alias-markdown-citation: rgb(53, 54, 56) !important;
  --dsw-alias-markdown-tag: rgb(44, 44, 46) !important;
  --dsw-alias-markdown-inline-code: rgb(44, 44, 46) !important;
  --dsw-alias-markdown-code-segment-unselected: rgb(27, 27, 28) !important;
  --dsw-alias-markdown-placeholder: rgb(101, 103, 107) !important;
}
body:not([data-ds-dark-theme]) {
  --dsw-alias-bg-base: rgba(255, 255, 255, 0.00) !important;
  --dsw-alias-bg-layer-1: rgba(255, 255, 255, 0.00) !important;
  --dsw-alias-bg-layer-2: rgba(255, 255, 255, 0.00) !important;
  --dsw-alias-bg-layer-3: rgba(255, 255, 255, 0.00) !important;
  --dsw-alias-bg-module-platform: rgba(255, 255, 255, 0.00) !important;
  --dsw-alias-bg-overlay: rgba(255, 255, 255, 0.60) !important;
  --dsw-alias-toast-bg: rgba(60, 60, 61, 0.92) !important;
  --dsw-alias-tooltip-bg: rgba(33, 33, 35, 0.94) !important;
  --dsw-specific-sidebar-fill: rgba(255, 255, 255, 0.00) !important;
  --dsw-specific-menu: rgba(255, 255, 255, 0.50) !important;
  --dsw-specific-selector: rgba(255, 255, 255, 0.45) !important;
  --dsw-specific-tip: rgba(255, 255, 255, 0.40) !important;
  --dsw-specific-input-major: rgba(255, 255, 255, 0.35) !important;
  --dsw-specific-login-input: rgba(255, 255, 255, 0.45) !important;
  --dsw-specific-bubble: rgba(255, 255, 255, 0.00) !important;
  --dsw-specific-bubble-highlight: rgba(255, 255, 255, 0.00) !important;
  --dsw-hovercard-bg: rgba(255, 255, 255, 0.55) !important;
  --dsw-alias-markdown-code-block: rgba(250, 250, 250, 0.00) !important;
  --dsw-alias-markdown-code-block-banner: rgba(255, 255, 255, 0.00) !important;
  --dsw-alias-label-secondary: var(--glass-txt-secondary, rgb(53, 54, 56)) !important;
  --dsw-alias-label-tertiary: var(--glass-txt-tertiary, rgb(84, 85, 87)) !important;
  --dsw-alias-label-caption: var(--glass-txt-caption, rgb(97, 102, 107)) !important;
  --dsw-alias-label-dimmed: var(--glass-txt-dimmed, rgb(129, 133, 140)) !important;
  --dsw-alias-markdown-placeholder: var(--glass-txt-placeholder, rgb(162, 164, 166)) !important;
  --dsw-alias-label-primary: var(--glass-txt-primary, rgb(15, 17, 21)) !important;
  --dsw-alias-label-primary-dimmed: rgb(53, 54, 56) !important;
  --dsw-alias-label-primary-bluish: rgb(14, 48, 116) !important;
  --dsw-alias-markdown-citation: rgb(235, 238, 242) !important;
  --dsw-alias-markdown-tag: rgb(241, 243, 245) !important;
  --dsw-alias-markdown-inline-code: rgb(235, 238, 242) !important;
  --dsw-alias-markdown-code-segment-unselected: rgb(241, 243, 245) !important;
  --dsw-alias-state-warn-label: rgb(180, 120, 0) !important;
  --dsw-alias-label-secondary: var(--glass-txt-secondary, rgb(53, 54, 56)) !important;
  --dsw-alias-label-tertiary: var(--glass-txt-tertiary, rgb(84, 85, 87)) !important;
  --dsw-alias-label-caption: var(--glass-txt-caption, rgb(97, 102, 107)) !important;
  --dsw-alias-label-dimmed: var(--glass-txt-dimmed, rgb(129, 133, 140)) !important;
  --dsw-alias-markdown-placeholder: var(--glass-txt-placeholder, rgb(162, 164, 166)) !important;
}
"""

// MARK: - 后端控制器（spawn 内置 dsh，解析 URL，管理生命周期）

final class BackendController: NSObject, ObservableObject {
    static let shared = BackendController()

    @Published var url: URL?
    @Published var errorText: String?

    private var process: Process?
    private var captured = ""

    var homePath: String {
        if let env = ProcessInfo.processInfo.environment["DSH_HOME"], !env.isEmpty {
            return env
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".dsh")
    }

    var logPath: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("DeepSeek Harness Glass.log")
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil
        )
    }

    @objc private func appWillTerminate() {
        shutdown()
    }

    /// 终止后端子进程（退出/被杀时调用，避免孤儿进程）。
    func shutdown() {
        if let p = process, p.isRunning {
            p.terminate()
        }
    }

    private func appendLog(_ text: String) {
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: logPath))
        }
    }

    func start() {
        guard process == nil else { return }
        let resources = Bundle.main.resourceURL!
        let node = resources.appendingPathComponent("node/node")
        let bin = resources
            .appendingPathComponent("backend/node_modules/@deepseek-ai/dsh/lib/bin.js")

        guard FileManager.default.fileExists(atPath: node.path) else {
            errorText = "缺少内置 Node 运行时：\(node.path)"
            return
        }
        guard FileManager.default.fileExists(atPath: bin.path) else {
            errorText = "缺少内置 dsh 后端：\(bin.path)"
            return
        }
        try? FileManager.default.createDirectory(atPath: homePath, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = node
        proc.arguments = ["--expose-internals", bin.path, "web", "--port", "0"]
        var env = ProcessInfo.processInfo.environment
        env["DSH_HOME"] = homePath
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.handleOutput(text)
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.url == nil {
                    self.errorText = "后端启动失败（code=\(p.terminationStatus)）。日志：\(self.logPath)"
                } else {
                    self.url = nil
                    self.errorText = "后端意外退出（code=\(p.terminationStatus)）。请重新打开应用。日志：\(self.logPath)"
                }
                self.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            errorText = "无法启动后端：\(error.localizedDescription)"
        }
    }

    private func handleOutput(_ text: String) {
        appendLog(text)
        captured += text
        if url == nil,
           let range = captured.range(
               of: #"dsh web:\s+(https?://127\.0\.0\.1(?::\d+)?/?\S*)"#,
               options: .regularExpression
           ) {
            let match = String(captured[range])
            if let u = match.split(separator: " ").last.map(String.init),
               let parsed = URL(string: u) {
                url = parsed
            }
        }
    }
}

// MARK: - 动态反色文字（苹果式自适应：按窗口背后壁纸亮度取反色）

final class DynamicContrast {
    static let shared = DynamicContrast()
    static let didChange = Notification.Name("DynamicContrast.didChange")

    /// 0 = 背景很暗，1 = 背景很亮
    private(set) var luminance: Double = 0.5

    private struct Endpoint { let r: Double; let g: Double; let b: Double }
    /// 背景暗 -> 文字亮（反色）
    private let darkBackdrop: [String: Endpoint] = [
        "primary": Endpoint(r: 240, g: 242, b: 245),
        "secondary": Endpoint(r: 225, g: 229, b: 238),
        "tertiary": Endpoint(r: 207, g: 211, b: 214),
        "caption": Endpoint(r: 173, g: 178, b: 184),
        "dimmed": Endpoint(r: 151, g: 157, b: 166),
        "placeholder": Endpoint(r: 127, g: 130, b: 135),
    ]
    /// 背景亮 -> 文字深
    private let brightBackdrop: [String: Endpoint] = [
        "primary": Endpoint(r: 15, g: 17, b: 21),
        "secondary": Endpoint(r: 53, g: 54, b: 56),
        "tertiary": Endpoint(r: 84, g: 85, b: 87),
        "caption": Endpoint(r: 97, g: 102, b: 107),
        "dimmed": Endpoint(r: 129, g: 133, b: 140),
        "placeholder": Endpoint(r: 162, g: 164, b: 166),
    ]

    private(set) var colors: [String: String] = [:]

    func setLuminance(_ l: Double) {
        let clamped = min(max(l, 0), 1)
        // 苹果式阈值翻转：亮背景 -> 深字，暗背景 -> 浅字（不做中间灰渐变）。
        // 带 0.45/0.55 迟滞，避免在阈值附近来回闪。
        let target: Double
        if luminance >= 0.5 {
            target = clamped < 0.45 ? 0.0 : 1.0
        } else {
            target = clamped > 0.55 ? 1.0 : 0.0
        }
        guard abs(target - luminance) > 0.01 || colors.isEmpty else { return }
        luminance = target
        colors = Self.interpolate(from: darkBackdrop, to: brightBackdrop, t: target)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func interpolate(
        from: [String: Endpoint], to: [String: Endpoint], t: Double
    ) -> [String: String] {
        var out: [String: String] = [:]
        for (key, a) in from {
            guard let b = to[key] else { continue }
            let r = Int((a.r + (b.r - a.r) * t).rounded())
            let g = Int((a.g + (b.g - a.g) * t).rounded())
            let bl = Int((a.b + (b.b - a.b) * t).rounded())
            out[key] = "rgb(\(r), \(g), \(bl))"
        }
        return out
    }

    /// 生成注入 WKWebView 的 JS：把当前颜色写进 --glass-txt-* CSS 变量。
    var jsPayload: String {
        var lines: [String] = []
        for (key, color) in colors {
            lines.append("r.style.setProperty('--glass-txt-\(key)','\(color)')")
        }
        return "(()=>{var r=document.documentElement;\(lines.joined(separator: ";"));})()"
    }
}

// MARK: - WKWebView（透明 + CSS 注入）

final class GlassWebViewController: NSViewController, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded = false
    private var contrastObserver: NSObjectProtocol?

    init(url: URL) {
        let config = WKWebViewConfiguration()
        let css = GLASS_CSS
        let script = WKUserScript(
            source: """
            (function () {
              if (!document.getElementById('dsh-glass-style')) {
                var s = document.createElement('style')
                s.id = 'dsh-glass-style'
                s.textContent = `\(css)`
                document.documentElement.appendChild(s)
              }
              // 层级磨砂：给所有带可见背景的元素叠加 backdrop-filter。
              // （网页无法采样原生玻璃，但能真实模糊其下的页面内容——弹窗、
              // 菜单、输入框下方的文字会被高斯打散，形成第二层磨砂观感。）
              function dshGlassAlpha(el) {
                try {
                  var bg = getComputedStyle(el).backgroundColor || ''
                  if (bg === 'transparent') return 0
                  if (bg.indexOf('rgba') !== 0) return 1
                  var inner = bg.substring(bg.indexOf('(') + 1, bg.lastIndexOf(')'))
                  var parts = inner.split(',')
                  return parts.length > 3 ? parseFloat(parts[3]) : 1
                } catch (e) { return 0 }
              }
              function dshGlassSweep(root) {
                if (!root || !root.querySelectorAll) return
                var els = root.querySelectorAll('div,section,aside,form,span,button,input,textarea,ul,li,nav')
                for (var i = 0; i < els.length; i++) {
                  var el = els[i]
                  if (el.getAttribute('data-dsh-blur')) continue
                  if (dshGlassAlpha(el) > 0.05) {
                    el.setAttribute('data-dsh-blur', '1')
                    el.style.backdropFilter = 'blur(18px) saturate(1.4)'
                    el.style.webkitBackdropFilter = 'blur(18px) saturate(1.4)'
                  }
                }
              }
              dshGlassSweep(document.body)
              var dshMo = new MutationObserver(function (muts) {
                for (var i = 0; i < muts.length; i++) {
                  var added = muts[i].addedNodes
                  for (var j = 0; j < added.length; j++) {
                    if (added[j].nodeType === 1) dshGlassSweep(added[j])
                  }
                }
              })
              dshMo.observe(document.body, { childList: true, subtree: true })
            })()
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        contrastObserver = NotificationCenter.default.addObserver(
            forName: DynamicContrast.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyContrast()
        }
        webView.load(URLRequest(url: url))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        view = webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        applyContrast()
    }

    /// 把动态反色文字颜色推进页面（初始 + 每次背景亮度变化）。
    private func applyContrast() {
        let js = DynamicContrast.shared.jsPayload
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

struct GlassWebView: NSViewControllerRepresentable {
    let url: URL
    func makeNSViewController(context: Context) -> GlassWebViewController {
        GlassWebViewController(url: url)
    }
    func updateNSViewController(_ vc: GlassWebViewController, context: Context) {}
}

// MARK: - 窗口配置器（在布局时机直接配置 NSWindow，确保内容+玻璃顶到窗口最顶端）

/// 挂进窗口后立刻把窗口配置成"透明+全尺寸内容"，保证玻璃覆盖到窗口最顶端。
struct WindowAnchorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.layoutIfNeeded()
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: - 界面

struct ContentView: View {
    @ObservedObject var backend = BackendController.shared

    var body: some View {
        Group {
            if let url = backend.url {
                GlassWebView(url: url)
            } else if let err = backend.errorText {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                    Text("DeepSeek Harness 启动失败")
                        .font(.title2.bold())
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("重新启动") { backend.start() }
                        .controlSize(.large)
                }
                .padding(40)
            } else {
                ProgressView("正在启动 DeepSeek Harness…")
                    .controlSize(.large)
            }
        }
        .background(
            WindowAnchorView()
                .frame(width: 0, height: 0)
        )
        .frame(minWidth: 880, minHeight: 600)
    }
}

/// NSHostingView 子类：安全区归零，SwiftUI 内容与玻璃效果铺满整个窗口，
/// 覆盖标题栏拖动条区域（诊断显示系统默认报 safeAreaInsets.top = 32）。
final class ZeroSafeAreaHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

// MARK: - App 入口（AppKit 手工建窗：styleMask 从一开始就带 fullSizeContentView，
//         确保内容+玻璃顶到窗口最顶端，覆盖标题栏拖动条）

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DynamicContrast.shared.setLuminance(0.5)
        BackendController.shared.start()
        installSignalHandlers()
        buildMenu()
        buildWindow()
        startBackdropSampling()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 手工创建窗口：fullSizeContentView 在创建时生效，内容真正铺满整窗。
    private func buildWindow() {
        let content = ContentView()
            .ignoresSafeArea()
            .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
            .frame(minWidth: 880, minHeight: 600)

        let hosting = ZeroSafeAreaHostingView(rootView: content)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentMinSize = NSSize(width: 880, height: 600)
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)

        // 几何诊断：窗口各层边界写进日志，用于定位顶部"玻璃差一截"的问题。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logGeometry()
        }
    }

    // MARK: 背景亮度采样（动态反色文字）

    private var wallpaperURL: URL?
    private var wallpaperSmall: NSBitmapImageRep?
    private var sampleTimer: Timer?

    private func startBackdropSampling() {
        sampleBackdrop()
        // 只在启动和每 60 秒检查一次壁纸变化（换壁纸时重新决策一次）。
        // 不再跟随窗口位置：拖动窗口不会改变文字颜色（苹果原则：大表面不翻转）。
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.sampleBackdrop()
        }
    }

    /// 采样整张壁纸的平均亮度（0=暗 1=亮），驱动文字反色。窗口位置无关。
    private func sampleBackdrop() {
        guard let screen = window?.screen ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        if url != wallpaperURL {
            wallpaperURL = url
            wallpaperSmall = Self.downsample(URL: url)
        }
        guard let rep = wallpaperSmall else { return }
        guard let L = Self.averageLuminance(
            rep, x0: 0, y0: 0, x1: rep.pixelsWide, y1: rep.pixelsHigh
        ) else { return }
        DynamicContrast.shared.setLuminance(L)
        diagLog("[backdrop] luminance=\(String(format: "%.2f", L))")
    }

    private static func downsample(URL url: URL) -> NSBitmapImageRep? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let w = 96
        let h = max(1, Int(Double(w) * (img.size.height / max(img.size.width, 1))))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func averageLuminance(
        _ rep: NSBitmapImageRep, x0: Int, y0: Int, x1: Int, y1: Int
    ) -> Double? {
        guard x1 > x0, y1 > y0, let data = rep.bitmapData else { return nil }
        let bpr = rep.bytesPerRow
        var total = 0.0
        var count = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = y * bpr + x * 4
                let r = Double(data[i]) / 255.0
                let g = Double(data[i + 1]) / 255.0
                let b = Double(data[i + 2]) / 255.0
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    /// 诊断行写日志（best-effort）。
    private func diagLog(_ line: String) {
        let text = line + "\n"
        if let h = FileHandle(forWritingAtPath: BackendController.shared.logPath) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: BackendController.shared.logPath))
        }
    }

    private func logGeometry() {
        guard let w = window, let cv = w.contentView else { return }
        let lines = [
            "window.frame=\(w.frame)",
            "contentView.frame=\(cv.frame)",
            "contentLayoutRect=\(w.contentLayoutRect)",
            "styleMask=0x\(String(w.styleMask.rawValue, radix: 16)) fullSize=\(w.styleMask.contains(.fullSizeContentView))",
            "titleVisibility=\(w.titleVisibility.rawValue)",
            "cv.safeAreaInsets=\(cv.safeAreaInsets)",
            "cv.frame-in-layout=\(w.contentLayoutRect.height - cv.frame.height)",
        ]
        let text = "[geometry] " + lines.joined(separator: " | ") + "\n"
        FileHandle.standardError.write(Data(text.utf8))
        if let h = FileHandle(forWritingAtPath: BackendController.shared.logPath) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: BackendController.shared.logPath))
        }
    }

    /// 手工菜单：关于/退出 + Harness 快捷入口。
    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "关于 DeepSeek Harness",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "退出 DeepSeek Harness",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let harnessMenuItem = NSMenuItem()
        mainMenu.addItem(harnessMenuItem)
        let harnessMenu = NSMenu(title: "Harness")
        harnessMenu.addItem(
            withTitle: "打开配置目录（DSH_HOME）",
            action: #selector(AppDelegate.openHome(_:)),
            keyEquivalent: "")
        harnessMenu.addItem(
            withTitle: "打开后端日志",
            action: #selector(AppDelegate.openLog(_:)),
            keyEquivalent: "")
        harnessMenuItem.submenu = harnessMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openHome(_ sender: Any?) {
        let home = BackendController.shared.homePath
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: home))
    }

    @objc private func openLog(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: BackendController.shared.logPath))
    }

    /// 被 kill/SIGINT 时也走优雅退出：先杀掉 dsh 子进程，不留孤儿。
    private func installSignalHandlers() {
        signal(SIGTERM) { _ in
            BackendController.shared.shutdown()
            exit(0)
        }
        signal(SIGINT) { _ in
            BackendController.shared.shutdown()
            exit(0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
