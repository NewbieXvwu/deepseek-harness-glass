import AppKit
import SwiftUI

/// 统一封装单测环境中的 AppKit 临时窗口生命周期管理，
/// 物理杜绝 CoreAnimation 异步窗口动画在单测结束时引发的 EXC_BAD_ACCESS (SIGSEGV 11) 悬垂指针 (UAF) 崩溃。
@MainActor
enum IsolatedTestWindowHarness {
    /// 在完全隔离、禁用动画且确定性回收的 NSWindow 容器中装载 SwiftUI 视图执行断言。
    @discardableResult
    static func withHostedView<V: View, R>(
        _ view: V,
        size: NSSize = NSSize(width: 960, height: 720),
        settleTime: TimeInterval = 0.05,
        body: (NSHostingView<V>) throws -> R
    ) rethrows -> R {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        if settleTime > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(settleTime))
        }
        defer {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        return try body(host)
    }

    /// 在完全隔离、禁用动画且确定性回收的 NSWindow 容器中装载 SwiftUI 视图执行异步断言。
    @discardableResult
    static func withHostedViewAsync<V: View, R>(
        _ view: V,
        size: NSSize = NSSize(width: 960, height: 720),
        settleTime: TimeInterval = 0.05,
        body: (NSHostingView<V>) async throws -> R
    ) async rethrows -> R {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        if settleTime > 0 {
            try? await Task.sleep(nanoseconds: UInt64(settleTime * 1_000_000_000))
        }
        defer {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        return try await body(host)
    }
}
