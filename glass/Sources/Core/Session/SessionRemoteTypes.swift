import Foundation

struct SessionSeq: RawRepresentable, Codable, Hashable, Sendable, Comparable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct SessionLogOffset: RawRepresentable, Codable, Hashable, Sendable, Comparable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct SessionRequestID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }

    static func fresh() -> Self { .init(rawValue: UUID().uuidString.lowercased()) }
}

enum SessionAddress: Codable, Hashable, Sendable {
    case session(sessionID: String)
    case subagent(parentSessionID: String, childSessionID: String, mode: SubagentMode)

    enum SubagentMode: String, Codable, Sendable { case oneShot = "one-shot", continuable }

    private enum CodingKeys: String, CodingKey { case kind, sessionId, parentSessionId, childSessionId, mode }
    private enum Kind: String, Codable { case session, subagent }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .session:
            self = .session(sessionID: try container.decode(String.self, forKey: .sessionId))
        case .subagent:
            self = .subagent(
                parentSessionID: try container.decode(String.self, forKey: .parentSessionId),
                childSessionID: try container.decode(String.self, forKey: .childSessionId),
                mode: try container.decode(SubagentMode.self, forKey: .mode)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .session(sessionID):
            try container.encode(Kind.session, forKey: .kind)
            try container.encode(sessionID, forKey: .sessionId)
        case let .subagent(parentSessionID, childSessionID, mode):
            try container.encode(Kind.subagent, forKey: .kind)
            try container.encode(parentSessionID, forKey: .parentSessionId)
            try container.encode(childSessionID, forKey: .childSessionId)
            try container.encode(mode, forKey: .mode)
        }
    }
}
