import Foundation

struct RemoteSessionProjectionBaseline: Codable, Sendable, Equatable {
    let asOfSeq: SessionSeq
    let values: [String: RemoteJSONValue]
}

struct RemoteSessionWireHeader: Codable, Sendable, Equatable {
    let version: Int
    let id: String
    let createdAt: Int64
    let cwd: String?
    let parentSession: String?
    let seedLength: Int?
    let origin: String?
    let delegationDepth: Int?
    let agentPreset: String?
}

struct RemoteSessionWireEvent: Codable, Sendable, Equatable {
    let type: String
    let seq: SessionSeq
    let time: Int64
    let data: RemoteJSONValue
    let ignorable: Bool?
    let sourceEventSeqs: [Int]?
    let surfaceOp: RemoteJSONValue?
}

enum RemoteSessionHistoryRecord: Codable, Sendable, Equatable {
    case event(RemoteSessionWireEvent)
    case chunks(RemoteSessionWireEvent)

    private enum CodingKeys: String, CodingKey { case type, event }
    private enum Kind: String, Codable { case event, chunks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let event = try container.decode(RemoteSessionWireEvent.self, forKey: .event)
        switch try container.decode(Kind.self, forKey: .type) {
        case .event: self = .event(event)
        case .chunks: self = .chunks(event)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .event(event):
            try container.encode(Kind.event, forKey: .type)
            try container.encode(event, forKey: .event)
        case let .chunks(event):
            try container.encode(Kind.chunks, forKey: .type)
            try container.encode(event, forKey: .event)
        }
    }

    var event: RemoteSessionWireEvent {
        switch self { case let .event(event), let .chunks(event): event }
    }

    var firstSeq: SessionSeq { event.seq }

    var lastSeq: SessionSeq {
        guard case .chunks = self,
              case let .object(data) = event.data
        else { return event.seq }
        let memberCount: Int
        if event.type == "chunkrow/tool-call-chunks", case let .array(args)? = data["args"] {
            memberCount = args.count
        } else if (event.type == "chunkrow/text-chunks" || event.type == "chunkrow/reasoning-chunks"),
                  case let .array(texts)? = data["texts"] {
            memberCount = texts.count
        } else {
            return event.seq
        }
        return .init(rawValue: event.seq.rawValue + max(0, memberCount - 1))
    }
}

struct RemoteSessionPageValue: Codable, Sendable, Equatable {
    let records: [RemoteSessionHistoryRecord]
    let hasMore: Bool
}

enum RemoteSessionFollowFrame: Codable, Sendable, Equatable {
    case snapshot(
        header: RemoteSessionWireHeader,
        cursor: SessionSeq,
        records: [RemoteSessionHistoryRecord],
        hasMore: Bool,
        projections: RemoteSessionProjectionBaseline
    )
    case event(RemoteSessionWireEvent)

    private enum CodingKeys: String, CodingKey { case type, header, cursor, records, hasMore, projections, event }
    private enum Kind: String, Codable { case snapshot, event }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .snapshot:
            self = .snapshot(
                header: try container.decode(RemoteSessionWireHeader.self, forKey: .header),
                cursor: try container.decode(SessionSeq.self, forKey: .cursor),
                records: try container.decode([RemoteSessionHistoryRecord].self, forKey: .records),
                hasMore: try container.decode(Bool.self, forKey: .hasMore),
                projections: try container.decode(RemoteSessionProjectionBaseline.self, forKey: .projections)
            )
        case .event:
            self = .event(try container.decode(RemoteSessionWireEvent.self, forKey: .event))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .snapshot(header, cursor, records, hasMore, projections):
            try container.encode(Kind.snapshot, forKey: .type)
            try container.encode(header, forKey: .header)
            try container.encode(cursor, forKey: .cursor)
            try container.encode(records, forKey: .records)
            try container.encode(hasMore, forKey: .hasMore)
            try container.encode(projections, forKey: .projections)
        case let .event(event):
            try container.encode(Kind.event, forKey: .type)
            try container.encode(event, forKey: .event)
        }
    }
}

struct RemoteSessionQueuedItem: Codable, Sendable, Equatable, Identifiable {
    enum Placement: String, Codable, Sendable { case queued, steering, context }

    let id: String
    let placement: Placement
    let rpcId: SessionRequestID?
    let message: Message

    struct Message: Codable, Sendable, Equatable {
        let id: String
        let content: [RemoteJSONValue]
    }
}

struct RemoteSessionJob: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable { case running, stopping, completed, killed, failed }

    let id: String
    let kind: String
    let label: String
    let status: Status
    let detail: String?
    let startedAt: Int64
    let finishedAt: Int64?
}

struct RemoteSessionControlBaseline: Codable, Sendable, Equatable {
    let queues: [String: [RemoteSessionQueuedItem]]
    let jobs: [String: [RemoteSessionJob]]
    let projections: [String: RemoteSessionProjectionBaseline]
}

enum RemoteSessionControlFrame: Codable, Sendable, Equatable {
    case baseline(RemoteSessionControlBaseline)
    case queue(sessionID: String, items: [RemoteSessionQueuedItem])
    case jobs(sessionID: String, jobs: [RemoteSessionJob])
    case projection(sessionID: String, key: String, value: RemoteJSONValue, seq: SessionSeq)

    private enum CodingKeys: String, CodingKey { case type, value, sessionId, items, jobs, key, seq }
    private enum Kind: String, Codable { case baseline, queue, jobs, projection }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .baseline:
            self = .baseline(try container.decode(RemoteSessionControlBaseline.self, forKey: .value))
        case .queue:
            self = .queue(
                sessionID: try container.decode(String.self, forKey: .sessionId),
                items: try container.decode([RemoteSessionQueuedItem].self, forKey: .items)
            )
        case .jobs:
            self = .jobs(
                sessionID: try container.decode(String.self, forKey: .sessionId),
                jobs: try container.decode([RemoteSessionJob].self, forKey: .jobs)
            )
        case .projection:
            self = .projection(
                sessionID: try container.decode(String.self, forKey: .sessionId),
                key: try container.decode(String.self, forKey: .key),
                value: try container.decode(RemoteJSONValue.self, forKey: .value),
                seq: try container.decode(SessionSeq.self, forKey: .seq)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .baseline(value):
            try container.encode(Kind.baseline, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .queue(sessionID, items):
            try container.encode(Kind.queue, forKey: .type)
            try container.encode(sessionID, forKey: .sessionId)
            try container.encode(items, forKey: .items)
        case let .jobs(sessionID, jobs):
            try container.encode(Kind.jobs, forKey: .type)
            try container.encode(sessionID, forKey: .sessionId)
            try container.encode(jobs, forKey: .jobs)
        case let .projection(sessionID, key, value, seq):
            try container.encode(Kind.projection, forKey: .type)
            try container.encode(sessionID, forKey: .sessionId)
            try container.encode(key, forKey: .key)
            try container.encode(value, forKey: .value)
            try container.encode(seq, forKey: .seq)
        }
    }
}
