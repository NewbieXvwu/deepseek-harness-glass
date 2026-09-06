import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Typed read-only view of the official `goal` Session projection. Goal mutation
/// responses carry only a compare-and-set ref; this adapter therefore accepts
/// only the Host's whole current projection and never folds `goal/change` events
/// or acknowledges a mutation as though it were state.
struct CoreGoalProjection: Equatable {
    enum Phase: String, Equatable {
        case active
        case paused
        case blocked
        case complete
    }

    struct BlockedReason: Equatable {
        let code: String
        let message: String
    }

    let id: String
    let revision: Int
    let objective: String
    let phase: Phase
    let blockedReason: BlockedReason?
    let maxGoalRounds: Int
    let roundsStarted: Int
    let createdAt: Int
    let updatedAt: Int

    init?(projection: JSONValue) {
        guard let root = projection.objectValue,
              let goal = root["goal"]?.objectValue,
              let id = goal["id"]?.stringValue,
              !id.isEmpty,
              let revision = goal["revision"]?.nonNegativeInteger,
              revision > 0,
              let objective = goal["objective"]?.stringValue,
              !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let phaseRaw = goal["phase"]?.stringValue,
              let phase = Phase(rawValue: phaseRaw),
              let maxGoalRounds = goal["maxGoalRounds"]?.nonNegativeInteger,
              maxGoalRounds > 0,
              let roundsStarted = root["roundsStarted"]?.nonNegativeInteger,
              let createdAt = root["createdAt"]?.nonNegativeInteger,
              let updatedAt = root["updatedAt"]?.nonNegativeInteger,
              updatedAt >= createdAt
        else { return nil }

        let decodedReason: BlockedReason?
        if let reason = goal["blockedReason"]?.objectValue {
            guard let code = reason["code"]?.stringValue,
                  !code.isEmpty,
                  let message = reason["message"]?.stringValue,
                  !message.isEmpty
            else { return nil }
            decodedReason = .init(code: code, message: message)
        } else {
            decodedReason = nil
        }
        guard (phase == .blocked) == (decodedReason != nil) else { return nil }

        self.id = id
        self.revision = revision
        self.objective = objective
        self.phase = phase
        self.blockedReason = decodedReason
        self.maxGoalRounds = maxGoalRounds
        self.roundsStarted = roundsStarted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One Core-only projection reader. Callers get `nil` for an absent/tombstoned or
/// malformed value and must render a safe absent state rather than guessing a
/// goal from local mutation requests.
@MainActor
enum SessionGoalProjectionReader {
    static func value(from store: SessionProjectionStore, sessionID: String) -> CoreGoalProjection? {
        guard let value = store.value(sessionID: sessionID, key: "goal"), value != .null else { return nil }
        return CoreGoalProjection(projection: value)
    }
}

private extension JSONValue {
    var nonNegativeInteger: Int? {
        guard let number = numberValue,
              number.rounded(.towardZero) == number,
              number >= 0,
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}
