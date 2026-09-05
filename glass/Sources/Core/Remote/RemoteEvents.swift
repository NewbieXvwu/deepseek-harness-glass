import Foundation

struct RemoteHostFacts: Codable, Sendable, Equatable {
    let home: String
}

struct RemoteEventReady: Codable, Sendable, Equatable {
    let clientId: String
    let host: RemoteHostFacts
}

enum RemoteEventDownlinkFrame: Codable, Sendable, Equatable {
    case ready(RemoteEventReady)
    case emit(event: String, args: [RemoteJSONValue])
    case waterfall(event: String, eventID: String, agentID: String, request: [String: RemoteJSONValue])
    case cancel(eventID: String)

    private enum CodingKeys: String, CodingKey { case type, clientId, host, event, args, eventId, agentId, request }
    private enum Kind: String, Codable { case ready, emit, waterfall, cancel }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .ready:
            self = .ready(.init(
                clientId: try container.decode(String.self, forKey: .clientId),
                host: try container.decode(RemoteHostFacts.self, forKey: .host)
            ))
        case .emit:
            self = .emit(
                event: try container.decode(String.self, forKey: .event),
                args: try container.decode([RemoteJSONValue].self, forKey: .args)
            )
        case .waterfall:
            self = .waterfall(
                event: try container.decode(String.self, forKey: .event),
                eventID: try container.decode(String.self, forKey: .eventId),
                agentID: try container.decode(String.self, forKey: .agentId),
                request: try container.decode([String: RemoteJSONValue].self, forKey: .request)
            )
        case .cancel:
            self = .cancel(eventID: try container.decode(String.self, forKey: .eventId))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .ready(ready):
            try container.encode(Kind.ready, forKey: .type)
            try container.encode(ready.clientId, forKey: .clientId)
            try container.encode(ready.host, forKey: .host)
        case let .emit(event, args):
            try container.encode(Kind.emit, forKey: .type)
            try container.encode(event, forKey: .event)
            try container.encode(args, forKey: .args)
        case let .waterfall(event, eventID, agentID, request):
            try container.encode(Kind.waterfall, forKey: .type)
            try container.encode(event, forKey: .event)
            try container.encode(eventID, forKey: .eventId)
            try container.encode(agentID, forKey: .agentId)
            try container.encode(request, forKey: .request)
        case let .cancel(eventID):
            try container.encode(Kind.cancel, forKey: .type)
            try container.encode(eventID, forKey: .eventId)
        }
    }
}

struct RemoteEventRejection: Codable, Sendable, Equatable {
    let name: String
    let message: String
    let code: String?
    let details: RemoteJSONValue?

    init(name: String, message: String, code: String? = nil, details: RemoteJSONValue? = nil) {
        self.name = name
        self.message = message
        self.code = code
        self.details = details
    }
}

enum RemoteEventReplyOutcome: Encodable, Sendable, Equatable {
    case next
    case result(RemoteJSONValue?)
    case rejected(RemoteEventRejection)

    private enum CodingKeys: String, CodingKey { case kind, value, error }
    private enum Kind: String, Encodable { case next, result, rejected }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .next:
            try container.encode(Kind.next, forKey: .kind)
        case let .result(value):
            try container.encode(Kind.result, forKey: .kind)
            try container.encodeIfPresent(value, forKey: .value)
        case let .rejected(error):
            try container.encode(Kind.rejected, forKey: .kind)
            try container.encode(error, forKey: .error)
        }
    }
}

struct RemoteEventResultArguments: Encodable, Sendable, Equatable {
    let clientId: String
    let eventId: String
    let outcome: RemoteEventReplyOutcome
}

struct RemoteEventChannel: Sendable {
    let generation: RemoteConnectionGeneration
    let ready: RemoteEventReady
    let events: AsyncThrowingStream<RemoteEventDownlinkFrame, Error>
    private let replyHandler: @Sendable (String, RemoteEventReplyOutcome) async throws -> Void

    init(
        generation: RemoteConnectionGeneration,
        ready: RemoteEventReady,
        events: AsyncThrowingStream<RemoteEventDownlinkFrame, Error>,
        replyHandler: @escaping @Sendable (String, RemoteEventReplyOutcome) async throws -> Void
    ) {
        self.generation = generation
        self.ready = ready
        self.events = events
        self.replyHandler = replyHandler
    }

    func reply(eventID: String, outcome: RemoteEventReplyOutcome) async throws {
        try await replyHandler(eventID, outcome)
    }
}

actor RemoteGenerationCounter {
    private var value: UInt64 = 0
    func next() -> RemoteConnectionGeneration {
        value &+= 1
        return .init(rawValue: value)
    }
}
