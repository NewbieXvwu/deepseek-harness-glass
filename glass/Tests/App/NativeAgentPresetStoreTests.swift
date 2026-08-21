import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeAgentPresetStoreTests: XCTestCase {
    func testRefreshPreservesHostRosterWithoutSynthesizingPresetFacts() async {
        let api = PresetAPI(roster: [
            preset(id: "system-first", trust: "system", isDefault: true, name: nil, description: "Host supplied", broken: nil),
            preset(id: "broken-user", trust: "user", isDefault: false, name: "Broken", description: nil, broken: "Host failure"),
        ])
        let store = NativeAgentPresetStore()

        await store.refresh(using: api)

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.presets.map(\.id), ["system-first", "broken-user"])
        XCTAssertEqual(store.presets.map(\.trust), ["system", "user"])
        XCTAssertEqual(store.presets.compactMap(\.broken), ["Host failure"])
        XCTAssertTrue(store.authorable)
        XCTAssertTrue(store.hasDocument)
    }

    func testCopyRereadsHostRosterRatherThanOptimisticallyAppendingRequest() async {
        let api = PresetAPI(roster: [preset(id: "standard", trust: "system", isDefault: true, name: "Standard", description: nil, broken: nil)])
        let store = NativeAgentPresetStore()
        await store.refresh(using: api)

        let accepted = await store.copy(.init(from: "standard", agentPreset: "copied", name: "Copied"), using: api)

        XCTAssertTrue(accepted)
        XCTAssertEqual(api.copyRequests.count, 1)
        XCTAssertEqual(api.copyRequests.first?.from, "standard")
        XCTAssertEqual(api.copyRequests.first?.agentPreset, "copied")
        XCTAssertEqual(api.copyRequests.first?.name, "Copied")
        XCTAssertEqual(api.listCalls, 2)
        XCTAssertEqual(store.presets.map(\.id), ["standard", "copied"])
        XCTAssertEqual(store.presets.last?.name, "Host copy name")
    }

    func testCopyFailureKeepsHostRosterAndDoesNotInsertLocalRow() async {
        let api = PresetAPI(
            roster: [preset(id: "standard", trust: "system", isDefault: true, name: nil, description: nil, broken: nil)],
            copyFails: true
        )
        let store = NativeAgentPresetStore()
        await store.refresh(using: api)

        let accepted = await store.copy(.init(from: "standard", agentPreset: "copied", name: nil), using: api)

        XCTAssertFalse(accepted)
        XCTAssertEqual(store.presets.map(\.id), ["standard"])
        XCTAssertEqual(api.listCalls, 1)
    }

    func testRemoveRereadsHostRosterAndDropsStaleSelectedDetail() async {
        let api = PresetAPI(roster: [
            preset(id: "standard", trust: "system", isDefault: true, name: nil, description: nil, broken: nil),
            preset(id: "custom", trust: "user", isDefault: false, name: "Custom", description: nil, broken: nil),
        ])
        let store = NativeAgentPresetStore()
        await store.refresh(using: api)
        XCTAssertTrue(await store.select(sessionID: "session", agentPreset: "custom", using: api))
        XCTAssertTrue(await store.read(agentPreset: "custom", using: api))

        let removed = await store.remove(agentPreset: "custom", using: api)

        XCTAssertTrue(removed)
        XCTAssertEqual(api.removeRequests, ["custom"])
        XCTAssertEqual(store.presets.map(\.id), ["standard"])
        XCTAssertNil(store.selectedPreset)
        XCTAssertNil(store.detail)
    }

    func testOpenDocumentShowsOnlyHostReturnedFallbackPathAndDropsItAfterRosterRefresh() async {
        let api = PresetAPI(roster: [preset(id: "custom", trust: "user", isDefault: false, name: nil, description: nil, broken: nil)])
        let store = NativeAgentPresetStore()
        await store.refresh(using: api)

        XCTAssertTrue(await store.openDocument(agentPreset: "custom", using: api))
        XCTAssertEqual(store.revealedPaths, ["custom": "/host/preset"])

        api.openedDocument = true
        XCTAssertTrue(await store.openDocument(agentPreset: "custom", using: api))
        XCTAssertEqual(store.revealedPaths, ["custom": "/host/preset"])

        api.removePresetFromRoster(id: "custom")
        await store.refresh(using: api)
        XCTAssertTrue(store.revealedPaths.isEmpty)
    }

    func testSelectionRequiresHostConfirmedSelectableRosterRow() async {
        let api = PresetAPI(
            roster: [preset(id: "standard", trust: "system", isDefault: true, name: nil, description: nil, broken: nil)],
            selectResponse: "unlisted"
        )
        let store = NativeAgentPresetStore()
        await store.refresh(using: api)

        let accepted = await store.select(sessionID: "session", agentPreset: "standard", using: api)

        XCTAssertFalse(accepted)
        XCTAssertNil(store.selectedPreset)
        XCTAssertEqual(api.selectRequests.count, 1)
        XCTAssertEqual(api.selectRequests.first?.0, "session")
        XCTAssertEqual(api.selectRequests.first?.1, "standard")
    }

    private func preset(
        id: String,
        trust: String,
        isDefault: Bool,
        name: String?,
        description: String?,
        broken: String?
    ) -> AgentPresetEntryDTO {
        .init(id: id, trust: trust, isDefault: isDefault, name: name, description: description, broken: broken)
    }

    private final class PresetAPI: NativeAgentPresetAPI, @unchecked Sendable {
        private var roster: [AgentPresetEntryDTO]
        private let copyFails: Bool
        private let selectResponse: String?
        private(set) var listCalls = 0
        private(set) var copyRequests: [AgentPresetCopyRequest] = []
        private(set) var removeRequests: [String] = []
        private(set) var selectRequests: [(String, String)] = []
        var openedDocument = false

        init(roster: [AgentPresetEntryDTO], copyFails: Bool = false, selectResponse: String? = nil) {
            self.roster = roster
            self.copyFails = copyFails
            self.selectResponse = selectResponse
        }

        func list() async throws -> AgentPresetListResponse {
            listCalls += 1
            return .init(presets: roster, authorable: true, hasDocument: true)
        }

        func select(sessionID: String, agentPreset: String) async throws -> AgentPresetSelectResponse {
            selectRequests.append((sessionID, agentPreset))
            return .init(agentPreset: selectResponse ?? agentPreset)
        }

        func read(agentPreset: String) async throws -> AgentPresetReadResponse {
            .init(agentPreset: agentPreset, trust: "user", content: "Host composition", name: "Host name", description: nil)
        }

        func copy(_ request: AgentPresetCopyRequest) async throws -> AgentPresetCopyResponse {
            copyRequests.append(request)
            if copyFails { throw DSHTransportError.network("offline") }
            roster.append(.init(id: request.agentPreset, trust: "user", isDefault: false, name: "Host copy name", description: "Host copied", broken: nil))
            return .init(agentPreset: request.agentPreset)
        }

        func openDocument(agentPreset _: String) async throws -> AgentPresetOpenDocumentResponse {
            .init(opened: openedDocument, path: openedDocument ? nil : "/host/preset")
        }

        func removePresetFromRoster(id: String) {
            roster.removeAll { $0.id == id }
        }

        func remove(agentPreset: String) async throws -> EmptyRPCResponse {
            removeRequests.append(agentPreset)
            roster.removeAll { $0.id == agentPreset }
            return .init()
        }
    }
}
