import AppKit
import XCTest

@testable import DeepSeekHarnessGlassApp

@MainActor
final class WindowCoordinatorTests: XCTestCase {
    func testWindowPolicyRetainsMigratedNativeGeometryAndTitlebarStrategy() {
        let initialContentSize = NativeWindowPolicy.initialContentSize
        let minimumContentSize = NativeWindowPolicy.minimumContentSize
        let styleMask = NativeWindowPolicy.styleMask
        let toolbarStyle = NativeWindowPolicy.toolbarStyle
        XCTAssertEqual(initialContentSize, NSSize(width: 1280, height: 840))
        XCTAssertEqual(minimumContentSize, NSSize(width: 880, height: 600))
        XCTAssertTrue(styleMask.contains(.titled))
        XCTAssertTrue(styleMask.contains(.closable))
        XCTAssertTrue(styleMask.contains(.miniaturizable))
        XCTAssertTrue(styleMask.contains(.resizable))
        XCTAssertTrue(styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(toolbarStyle, .unifiedCompact)
    }

    func testRestorationNamesAreStableAndNativeScoped() {
        let autosaveName = NativeWindowPolicy.frameAutosaveName
        let restorationIdentifier = NativeWindowPolicy.restorationIdentifier
        XCTAssertEqual(autosaveName, "DeepSeekHarnessGlass.MainWindow")
        XCTAssertEqual(restorationIdentifier, NSUserInterfaceItemIdentifier("DeepSeekHarnessGlass.MainWindow"))
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

    func testDockReopenDelegatesToTheExistingCoordinatorWithoutCreatingAShell() {
        let coordinator = WindowCoordinator()
        let app = DeepSeekHarnessGlassApp(windowCoordinator: coordinator)

        XCTAssertNil(coordinator.window)
        XCTAssertEqual(coordinator.showAndFocusInvocationCount, 0)
        XCTAssertTrue(app.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertEqual(coordinator.showAndFocusInvocationCount, 1)
        XCTAssertEqual(coordinator.lifecycle, .visible)
        XCTAssertNil(coordinator.window, "Dock reopen must focus a resident coordinator, not create a second shell")
    }

    func testReinstallReusesTheResidentWindowAndShellController() throws {
        let coordinator = WindowCoordinator()
        coordinator.install(presentation: NativeShellPresentation())
        let residentWindow = try XCTUnwrap(coordinator.window)
        let residentController = try XCTUnwrap(residentWindow.contentViewController)
        let initialFocusCount = coordinator.showAndFocusInvocationCount
        defer { residentWindow.orderOut(nil) }

        coordinator.install(presentation: NativeShellPresentation(mode: .conversation))

        XCTAssertTrue(coordinator.window === residentWindow)
        XCTAssertTrue(
            residentWindow.contentViewController === residentController,
            "installing a new presentation must not create a second native shell controller"
        )
        XCTAssertEqual(coordinator.showAndFocusInvocationCount, initialFocusCount + 1)
    }
}
