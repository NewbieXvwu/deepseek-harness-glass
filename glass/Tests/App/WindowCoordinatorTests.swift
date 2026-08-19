import AppKit
import XCTest

@testable import DeepSeekHarnessGlassApp
@testable import GlassUI

@MainActor
final class WindowCoordinatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(NativeWindowPolicy.frameAutosaveName)")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(NativeWindowPolicy.frameAutosaveName)")
        super.tearDown()
    }

    func testWindowPolicyPreservesNativeGeometryAndRestorationIdentity() {
        let window = NativeWindowPolicy.makeWindow()
        defer { window.close() }

        XCTAssertEqual(window.frame.size, NativeWindowPolicy.initialContentSize)
        XCTAssertEqual(window.contentMinSize, NativeWindowPolicy.minimumContentSize)
        XCTAssertEqual(window.minSize, NativeWindowPolicy.minimumContentSize)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.isRestorable)
        XCTAssertEqual(window.identifier, NativeWindowPolicy.restorationIdentifier)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
    }

    func testSavedFrameRestoresBeforeCentering() {
        let original = NativeWindowPolicy.makeWindow()
        let expected = NSRect(x: 117, y: 83, width: 1110, height: 720)
        original.setFrame(expected, display: false)
        NativeWindowPolicy.saveFrame(original)
        original.close()

        let restored = NativeWindowPolicy.makeWindow()
        defer { restored.close() }
        XCTAssertTrue(NativeWindowPolicy.restoreOrCenter(restored))
        XCTAssertEqual(restored.frame.integral, expected.integral)
    }

    func testFramePersistenceIsAvailableWithoutDisplayingAWindow() {
        let window = NativeWindowPolicy.makeWindow()
        defer { window.close() }

        window.setFrame(NSRect(x: 31, y: 47, width: 1000, height: 700), display: false)
        NativeWindowPolicy.saveFrame(window)
        XCTAssertTrue(
            UserDefaults.standard.object(forKey: "NSWindow Frame \(NativeWindowPolicy.frameAutosaveName)") != nil,
            "a close-to-menu-bar event can persist the native frame before orderOut"
        )
    }
}
