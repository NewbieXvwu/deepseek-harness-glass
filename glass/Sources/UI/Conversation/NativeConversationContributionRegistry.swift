import Combine
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Render context handed only to registered native conversation contributions.
/// It exposes read-only session identity and the Core store rather than browser
/// slots, DOM handles, or untyped Host payloads.
@MainActor
struct NativeConversationContributionContext {
    let sessionID: String?
    let sessionSnapshot: NativeWorkspaceStore.Snapshot
    let sessionStore: NativeSessionStore
}

/// The two strict RC8 header extension seats. Keeping actions and utilities
/// separate preserves the upstream title-cluster/utility spacing semantics.
enum NativeConversationHeaderSlot: String, Equatable {
    case actions
    case utilities
}

/// A disposable registration returned by one of the native contribution rings.
/// The nonce prevents a stale disposer from unregistering a later contribution
/// that deliberately reuses its id after teardown.
struct NativeConversationContributionRegistration: Hashable {
    fileprivate let id: String
    fileprivate let nonce: UUID
}

enum NativeConversationContributionRegistryError: Error, Equatable {
    case duplicateViewID(String)
    case duplicateHeaderContribution(slot: NativeConversationHeaderSlot, id: String)
}

/// RC8's `conversation.view` ledger represented as a native, scoped registry.
/// Chat is a stable built-in entry at order zero. Other views must supply a
/// real renderer; attempting to expose an unrenderable tab is rejected at the
/// typed boundary rather than producing a blank SwiftUI page.
@MainActor
final class NativeConversationViewRegistry: ObservableObject {
    typealias Renderer = @MainActor (NativeConversationContributionContext) -> AnyView

    private struct Entry {
        let tab: NativeConversationViewTab
        let order: Int
        let nonce: UUID
        let renderer: Renderer?
    }

    static let chatID = "chat"

    private var entries: [Entry] = [
        .init(
            tab: .init(id: chatID, label: OfficialUISpec.Text.chat),
            order: 0,
            nonce: UUID(),
            renderer: nil
        ),
    ]

    var registeredTabs: [NativeConversationViewTab] {
        entries.sorted { lhs, rhs in
            lhs.order == rhs.order ? lhs.tab.id < rhs.tab.id : lhs.order < rhs.order
        }.map(\.tab)
    }

    func resolve(selectedID: String?) -> NativeConversationViewTab? {
        let requestedID = selectedID ?? Self.chatID
        return registeredTabs.first { $0.id == requestedID }
            ?? registeredTabs.first { $0.id == Self.chatID }
    }

    func register(
        id: String,
        order: Int,
        label: String? = nil,
        renderer: @escaping Renderer
    ) throws -> NativeConversationContributionRegistration {
        guard !entries.contains(where: { $0.tab.id == id }) else {
            throw NativeConversationContributionRegistryError.duplicateViewID(id)
        }
        let nonce = UUID()
        objectWillChange.send()
        entries.append(.init(
            tab: .init(id: id, label: label ?? id),
            order: order,
            nonce: nonce,
            renderer: renderer
        ))
        return .init(id: id, nonce: nonce)
    }

    func unregister(_ registration: NativeConversationContributionRegistration) {
        guard let index = entries.firstIndex(where: {
            $0.tab.id == registration.id && $0.nonce == registration.nonce
        }), entries[index].tab.id != Self.chatID else { return }
        objectWillChange.send()
        entries.remove(at: index)
    }

    func render(
        selectedID: String?,
        context: NativeConversationContributionContext
    ) -> AnyView? {
        guard let active = resolve(selectedID: selectedID), active.id != Self.chatID,
              let renderer = entries.first(where: { $0.tab.id == active.id })?.renderer
        else { return nil }
        return renderer(context)
    }
}

/// Native additive projection of RC8's distinct
/// `conversation.session.header.actions` and `.utilities` list slots.
@MainActor
final class NativeConversationHeaderContributionRegistry: ObservableObject {
    typealias Renderer = @MainActor (NativeConversationContributionContext) -> AnyView

    private struct Entry {
        let id: String
        let order: Int
        let nonce: UUID
        let renderer: Renderer
    }

    private var entriesBySlot: [NativeConversationHeaderSlot: [Entry]] = [:]

    func register(
        slot: NativeConversationHeaderSlot,
        id: String,
        order: Int,
        renderer: @escaping Renderer
    ) throws -> NativeConversationContributionRegistration {
        guard !(entriesBySlot[slot] ?? []).contains(where: { $0.id == id }) else {
            throw NativeConversationContributionRegistryError.duplicateHeaderContribution(slot: slot, id: id)
        }
        let nonce = UUID()
        objectWillChange.send()
        entriesBySlot[slot, default: []].append(.init(id: id, order: order, nonce: nonce, renderer: renderer))
        return .init(id: id, nonce: nonce)
    }

    func unregister(_ registration: NativeConversationContributionRegistration) {
        for slot in NativeConversationHeaderSlot.allCases {
            guard let index = entriesBySlot[slot]?.firstIndex(where: {
                $0.id == registration.id && $0.nonce == registration.nonce
            }) else { continue }
            objectWillChange.send()
            entriesBySlot[slot]?.remove(at: index)
            if entriesBySlot[slot]?.isEmpty == true { entriesBySlot[slot] = nil }
            return
        }
    }

    func render(slot: NativeConversationHeaderSlot, context: NativeConversationContributionContext) -> [AnyView] {
        (entriesBySlot[slot] ?? [])
            .sorted { lhs, rhs in lhs.order == rhs.order ? lhs.id < rhs.id : lhs.order < rhs.order }
            .map { $0.renderer(context) }
    }
}

extension NativeConversationHeaderSlot: CaseIterable {}
