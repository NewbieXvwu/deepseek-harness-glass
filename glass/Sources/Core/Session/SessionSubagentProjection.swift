import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Typed RC8 subagent identity projection. `absent` is distinct from the
/// serializable `null` sentinel: the former means no projection capability was
/// supplied, while the latter means the Host folded no trusted descriptor.
enum CoreSubagentIdentityProjection: Equatable {
    enum Mode: String, Equatable { case oneShot = "one-shot", continuable }

    struct Identity: Equatable {
        let mode: Mode
        let label: String?
        let descriptorSeq: Int
    }

    case absent
    case noValidDescriptor
    case identity(Identity)
}

struct CoreSubagentTimingProjection: Equatable {
    struct Active: Equatable {
        let since: Int
        let through: Int
    }

    let settledMilliseconds: Int
    let active: Active?
}

@MainActor
enum SessionSubagentProjectionReader {
    static func identity(from store: SessionProjectionStore, sessionID: String) -> CoreSubagentIdentityProjection {
        guard let value = store.value(sessionID: sessionID, key: "subagent") else { return .absent }
        guard value != .null else { return .noValidDescriptor }
        guard let object = value.objectValue,
              let modeRaw = object["mode"]?.stringValue,
              let mode = CoreSubagentIdentityProjection.Mode(rawValue: modeRaw),
              let descriptorSeq = object["seq"]?.subagentNonNegativeInteger
        else { return .noValidDescriptor }
        let label = object["label"]?.stringValue
        guard mode != .continuable || (label?.isEmpty == false) else { return .noValidDescriptor }
        return .identity(.init(mode: mode, label: label, descriptorSeq: descriptorSeq))
    }

    static func timing(from store: SessionProjectionStore, sessionID: String) -> CoreSubagentTimingProjection? {
        guard let value = store.value(sessionID: sessionID, key: "subagentTiming"), value != .null,
              let object = value.objectValue,
              let settled = object["settledMs"]?.subagentNonNegativeInteger
        else { return nil }
        let active: CoreSubagentTimingProjection.Active?
        if let rawActive = object["active"]?.objectValue {
            guard let since = rawActive["since"]?.subagentNonNegativeInteger,
                  let through = rawActive["through"]?.subagentNonNegativeInteger,
                  through >= since
            else { return nil }
            active = .init(since: since, through: through)
        } else {
            active = nil
        }
        return .init(settledMilliseconds: settled, active: active)
    }
}

private extension JSONValue {
    var subagentNonNegativeInteger: Int? {
        guard let number = numberValue,
              number.rounded(.towardZero) == number,
              number >= 0,
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}
