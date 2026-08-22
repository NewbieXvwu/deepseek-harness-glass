import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeGoalDockTests: XCTestCase {
    func testVisibilityHidesAbsentCompleteAndOnlyMatchingClearMarker() throws {
        let active = goal(id: "goal-active", phase: "active")
        XCTAssertFalse(NativeGoalDockPresentation.isVisible(nil, locallyClearedGoalID: nil))
        XCTAssertFalse(NativeGoalDockPresentation.isVisible(goal(id: "goal-done", phase: "complete"), locallyClearedGoalID: nil))
        XCTAssertTrue(NativeGoalDockPresentation.isVisible(active, locallyClearedGoalID: nil))
        XCTAssertFalse(NativeGoalDockPresentation.isVisible(active, locallyClearedGoalID: "goal-active"))
        XCTAssertTrue(NativeGoalDockPresentation.isVisible(active, locallyClearedGoalID: "different-goal"))
    }

    func testPhaseAndHostBusinessFailureCopyUsesOfficialTokens() throws {
        XCTAssertEqual(NativeGoalDockPresentation.phaseLabel(for: .active), OfficialUISpec.Text.goalPhaseActive)
        XCTAssertEqual(NativeGoalDockPresentation.phaseLabel(for: .paused), OfficialUISpec.Text.goalPhasePaused)
        XCTAssertEqual(NativeGoalDockPresentation.phaseLabel(for: .blocked), OfficialUISpec.Text.goalPhaseBlocked)
        XCTAssertNil(NativeGoalDockPresentation.phaseLabel(for: .complete))
        XCTAssertEqual(
            NativeGoalDockPresentation.failureText(.init(message: "stale revision", code: "agent-busy")),
            "stale revision (agent-busy)"
        )
    }

    private func goal(id: String, phase: String) throws -> CoreGoalProjection {
        let value: JSONValue = .object([
            "goal": .object([
                "id": .string(id),
                "revision": .number(1),
                "objective": .string("Ship the native goal dock"),
                "phase": .string(phase),
                "maxGoalRounds": .number(4),
            ]),
            "roundsStarted": .number(0),
            "createdAt": .number(100),
            "updatedAt": .number(100),
        ])
        return try XCTUnwrap(CoreGoalProjection(projection: value), "Goal fixture must satisfy the strict RC8 projection decoder")
    }
}
