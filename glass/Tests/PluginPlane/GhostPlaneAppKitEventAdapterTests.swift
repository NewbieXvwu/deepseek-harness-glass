import AppKit
@testable import GlassCore
@testable import GlassPluginPlane
import XCTest

@MainActor
final class GhostPlaneAppKitEventAdapterTests: XCTestCase {
    func testKeyboardEventPreservesDOMKeyCodeModifiersAndRepeat() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift, .command],
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            characters: "A",
            charactersIgnoringModifiers: "a",
            isARepeat: true,
            keyCode: 0
        ))
        let bridged = GhostPlaneAppKitEventAdapter.keyboard(from: event, phase: .down)
        guard case .keyboard(let keyboard) = bridged else { return XCTFail("expected keyboard bridge event") }
        XCTAssertEqual(keyboard.phase, .down)
        XCTAssertEqual(keyboard.key, "A")
        XCTAssertEqual(keyboard.code, "KeyA")
        XCTAssertEqual(keyboard.location, 0)
        XCTAssertTrue(keyboard.modifiers.contains(.shift))
        XCTAssertTrue(keyboard.modifiers.contains(.command))
        XCTAssertTrue(keyboard.isRepeat)
        XCTAssertFalse(keyboard.isComposing)
    }
}
