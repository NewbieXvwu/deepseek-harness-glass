import AppKit
import XCTest

@testable import DeepSeekHarnessGlassApp

final class WindowCoordinatorTests: XCTestCase {
    func testWindowPolicyRetainsMigratedNativeGeometryAndTitlebarStrategy() {
        XCTAssertEqual(NativeWindowPolicy.initialContentSize, NSSize(width: 1280, height: 840))
        XCTAssertEqual(NativeWindowPolicy.minimumContentSize, NSSize(width: 880, height: 600))
        XCTAssertTrue(NativeWindowPolicy.styleMask.contains(.titled))
        XCTAssertTrue(NativeWindowPolicy.styleMask.contains(.closable))
        XCTAssertTrue(NativeWindowPolicy.styleMask.contains(.miniaturizable))
        XCTAssertTrue(NativeWindowPolicy.styleMask.contains(.resizable))
        XCTAssertTrue(NativeWindowPolicy.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(NativeWindowPolicy.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(NativeWindowPolicy.titlebarSeparatorStyle, .none)
    }

    func testRestorationNamesAreStableAndNativeScoped() {
        XCTAssertEqual(NativeWindowPolicy.frameAutosaveName, "DeepSeekHarnessGlass.MainWindow")
        XCTAssertEqual(
            NativeWindowPolicy.restorationIdentifier,
            NSUserInterfaceItemIdentifier("DeepSeekHarnessGlass.MainWindow")
        )
    }

    func testCloseToMenuBarAndReopenLifecycleTransitions() {
        var lifecycle = NativeWindowLifecycle.visible
        lifecycle.hideForClose()
        XCTAssertEqual(lifecycle, .hidden)

        lifecycle.reveal()
        XCTAssertEqual(lifecycle, .visible, "menu bar or Dock reopen must reveal the resident shell")

        lifecycle.minimize()
        XCTAssertEqual(lifecycle, .minimized)
        lifecycle.reveal()
        XCTAssertEqual(lifecycle, .visible, "reopen must deminiaturize before focusing")
    }
}
