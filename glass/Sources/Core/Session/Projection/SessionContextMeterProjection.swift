#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Read-only projection of RC8 token-meter `contextPressure`. The meter is an
/// informational Host fact, never a local billing/gating estimate: it renders
/// only when a provider supplied both a prompt-pressure figure and a positive
/// route capacity.
struct CoreContextMeterState: Equatable {
    let usedTokens: Int
    let contextWindow: Int
    let percent: Int

    /// Mirrors RC8 `contextOccupancy`: projectedTokens reflects an immediately
    /// compacted surface, while pressureTokens supports older Host projections.
    @MainActor
    static func value(from store: SessionProjectionStore, sessionID: String) -> Self? {
        value(projection: store.value(sessionID: sessionID, key: "contextPressure"))
    }

    static func value(projection: JSONValue?) -> Self? {
        guard let object = projection?.objectValue else { return nil }
        let selectedUsage = object["projectedTokens"] ?? object["pressureTokens"]
        guard let usedTokens = integer(selectedUsage),
              let contextWindow = integer(object["contextWindow"]),
              contextWindow > 0
        else { return nil }
        let rawPercent = Double(usedTokens) / Double(contextWindow) * 100
        guard rawPercent.isFinite else { return nil }
        return .init(
            usedTokens: usedTokens,
            contextWindow: contextWindow,
            percent: min(100, Int(rawPercent.rounded(.toNearestOrAwayFromZero)))
        )
    }

    static func integer(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue,
              number.isFinite,
              number >= 0,
              number.rounded(.towardZero) == number,
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}

/// Optional RC8 `contextBreakdown` composition. Its heuristic segments must
/// never be substituted for provider-anchored occupancy; the UI shows them only
/// as individually complete descriptive rows inside an available meter.
struct CoreContextMeterBreakdown: Equatable {
    let systemTokens: Int
    let toolsTokens: Int
    let messageTokens: Int

    @MainActor
    static func value(from store: SessionProjectionStore, sessionID: String) -> Self? {
        value(projection: store.value(sessionID: sessionID, key: "contextBreakdown"))
    }

    static func value(projection: JSONValue?) -> Self? {
        guard let object = projection?.objectValue,
              let systemTokens = CoreContextMeterState.integer(object["systemTokens"]),
              let toolsTokens = CoreContextMeterState.integer(object["toolsTokens"]),
              let messageTokens = CoreContextMeterState.integer(object["messageTokens"])
        else { return nil }
        return .init(systemTokens: systemTokens, toolsTokens: toolsTokens, messageTokens: messageTokens)
    }
}
