/// Pure, browser-local projection of RC8 `WorkspaceBrowser` drag ordering.
/// It deliberately has no SwiftUI or transport dependency so the same decision
/// is testable before a view commits a Host ordering RPC.
enum NativeWorkspaceBrowserOrdering {
    static let ungroupedAccountKey = ""
    /// Source: RC8 `stores.ts:10-16`; this account is browser-local and never
    /// represents a Host workspace membership bucket.
    static let flatSessionOrderKey = "__flat_session_order__"

    enum SessionGroupMode: Equatable {
        case workspace
        case flat
    }

    enum DropHalf: Equatable {
        case before
        case after
    }

    enum SessionOrderMode: Equatable {
        case manual
        case updated
    }

    enum WorkspaceDecision: Equatable {
        case noOp
        case host(workspaceID: String, beforeWorkspaceID: String?)
    }

    enum SessionDecision: Equatable {
        case noOp
        /// RC8 keeps an editable browser-local account for every group, even
        /// when the same move is also persisted through the Workspace Host.
        case host(sessionID: String, workspaceID: String, beforeSessionID: String?, viewOrder: [String])
        /// Ungrouped and `updated` account ordering must never write a Host
        /// workspace ordering mutation.
        case local(order: [String])
    }

    /// RC8 `reconciledSessionOrder`: retain each live stored id once, then
    /// append live Host ids that were not in the local ordering account.
    static func reconciledOrder(hostIDs: [String], storedOrder: [String]?) -> [String] {
        guard let storedOrder else { return hostIDs }
        let live = Set(hostIDs)
        var included = Set<String>()
        var result: [String] = []
        for id in storedOrder where live.contains(id) && included.insert(id).inserted {
            result.append(id)
        }
        for id in hostIDs where included.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// RC1 `WorkspaceBrowser` inserts the newly selected blank session at the
    /// front of a browser-local account. Duplicate identity is removed so the
    /// operation is idempotent across Host refreshes.
    static func orderPromotingBlankSession(_ sessionID: String, in existingOrder: [String]) -> [String] {
        [sessionID] + existingOrder.filter { $0 != sessionID }
    }

    /// Maps the target row half to RC8's `insertWorkspaceBefore` anchor and
    /// rejects self, original-position, and adjacent no-op drops.
    static func workspaceDecision(
        workspaceID: String,
        overWorkspaceID: String,
        half: DropHalf,
        workspaceIDs: [String]
    ) -> WorkspaceDecision {
        guard let targetIndex = workspaceIDs.firstIndex(of: overWorkspaceID) else { return .noOp }
        let anchor = half == .before ? overWorkspaceID : workspaceIDs[safe: targetIndex + 1]
        guard isEffectiveMove(sourceID: workspaceID, anchorID: anchor, ids: workspaceIDs) else { return .noOp }
        return .host(workspaceID: workspaceID, beforeWorkspaceID: anchor)
    }

    /// Maps the target row half to RC8's `insertSessionBefore` anchor. A
    /// successful move always updates the browser-local account, but only
    /// manually ordered real workspaces may write the Host order.
    static func sessionDecision(
        sessionID: String,
        accountKey: String,
        overSessionID: String,
        half: DropHalf,
        orderedSessionIDs: [String],
        orderMode: SessionOrderMode
    ) -> SessionDecision {
        guard let targetIndex = orderedSessionIDs.firstIndex(of: overSessionID) else { return .noOp }
        let anchor = half == .before ? overSessionID : orderedSessionIDs[safe: targetIndex + 1]
        guard isEffectiveMove(sourceID: sessionID, anchorID: anchor, ids: orderedSessionIDs) else { return .noOp }

        var nextOrder = orderedSessionIDs.filter { $0 != sessionID }
        let insertAt = anchor.flatMap { nextOrder.firstIndex(of: $0) } ?? nextOrder.endIndex
        nextOrder.insert(sessionID, at: insertAt)

        guard orderMode == .manual,
              accountKey != ungroupedAccountKey,
              accountKey != flatSessionOrderKey
        else {
            return .local(order: nextOrder)
        }
        return .host(
            sessionID: sessionID,
            workspaceID: accountKey,
            beforeSessionID: anchor,
            viewOrder: nextOrder
        )
    }

    private static func isEffectiveMove(sourceID: String, anchorID: String?, ids: [String]) -> Bool {
        guard anchorID != sourceID, let sourceIndex = ids.firstIndex(of: sourceID) else { return false }
        let anchorIndex = anchorID.flatMap { ids.firstIndex(of: $0) } ?? ids.count
        return anchorIndex != sourceIndex && anchorIndex != sourceIndex + 1
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
