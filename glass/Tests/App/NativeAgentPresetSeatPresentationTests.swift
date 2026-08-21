import XCTest

@testable import GlassCore
@testable import GlassUI

final class NativeAgentPresetSeatPresentationTests: XCTestCase {
    func testSeatIsAvailableOnlyForHostBlankSessionAndPrefersHostComposition() {
        let roster = [
            preset(id: "standard", isDefault: true, broken: nil),
            preset(id: "minimal", isDefault: false, broken: nil),
            preset(id: "broken", isDefault: false, broken: "Host failure"),
        ]
        let blank = session(id: "blank", blank: true, agentPreset: "minimal")
        let started = session(id: "started", blank: false, agentPreset: "minimal")

        XCTAssertTrue(NativeAgentPresetSeatPresentation.isAvailable(for: blank))
        XCTAssertFalse(NativeAgentPresetSeatPresentation.isAvailable(for: started))
        XCTAssertEqual(NativeAgentPresetSeatPresentation.currentID(session: blank, roster: roster), "minimal")
        XCTAssertEqual(NativeAgentPresetSeatPresentation.options(from: roster).map(\.id), ["standard", "minimal"])
    }

    func testSeatFallsBackOnlyToHostDefaultWhenSessionHasNoSelectableComposition() {
        let roster = [
            preset(id: "standard", isDefault: true, broken: nil),
            preset(id: "broken", isDefault: false, broken: "Host failure"),
        ]
        let empty = session(id: "empty", blank: true, agentPreset: nil)
        let stale = session(id: "stale", blank: true, agentPreset: "missing")

        XCTAssertEqual(NativeAgentPresetSeatPresentation.currentID(session: empty, roster: roster), "standard")
        XCTAssertEqual(NativeAgentPresetSeatPresentation.currentID(session: stale, roster: roster), "standard")
    }

    private func preset(id: String, isDefault: Bool, broken: String?) -> AgentPresetEntryDTO {
        .init(id: id, trust: "system", isDefault: isDefault, name: id, description: nil, broken: broken)
    }

    private func session(id: String, blank: Bool, agentPreset: String?) -> SessionSummaryDTO {
        .init(
            sessionId: id,
            updatedAt: 1,
            running: false,
            blank: blank,
            pendingInteraction: nil,
            parentSessionId: nil,
            origin: nil,
            cwd: nil,
            agentPreset: agentPreset,
            projections: nil
        )
    }
}
