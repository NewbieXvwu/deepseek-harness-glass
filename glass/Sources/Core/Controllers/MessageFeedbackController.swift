import Foundation

protocol MessageFeedbackControllerAPI: Sendable {
    func list(sessionID: String) async throws -> RemoteMessageFeedbackListResult
    func put(_ request: RemoteMessageFeedbackPutRequest) async throws -> RemoteMessageFeedbackPutResult
    func delete(_ request: RemoteMessageFeedbackDeleteRequest) async throws -> RemoteMessageFeedbackDeleteResult
}

enum RemoteMessageFeedbackRating: String, Codable, Sendable, Equatable {
    case positive
    case negative
}

struct RemoteMessageFeedbackVersion: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct RemoteMessageFeedbackItem: Codable, Sendable, Equatable {
    let messageId: String
    let rating: RemoteMessageFeedbackRating
    let note: String?
    let version: RemoteMessageFeedbackVersion
    let createdAt: Int
    let updatedAt: Int
}

struct RemoteMessageFeedbackListValue: Codable, Sendable, Equatable {
    let items: [RemoteMessageFeedbackItem]
}

struct RemoteMessageFeedbackPutRequest: Codable, Sendable, Equatable {
    let sessionId: String
    let messageId: String
    let rating: RemoteMessageFeedbackRating
    let note: String?
    let ifVersion: RemoteMessageFeedbackVersion?

    private enum CodingKeys: String, CodingKey {
        case sessionId, messageId, rating, note, ifVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(messageId, forKey: .messageId)
        try container.encode(rating, forKey: .rating)
        try container.encodeIfPresent(note, forKey: .note)
        if let ifVersion {
            try container.encode(ifVersion, forKey: .ifVersion)
        } else {
            try container.encodeNil(forKey: .ifVersion)
        }
    }
}

struct RemoteMessageFeedbackDeleteRequest: Codable, Sendable, Equatable {
    let sessionId: String
    let messageId: String
    let ifVersion: RemoteMessageFeedbackVersion
}

struct RemoteMessageFeedbackDeleteValue: Codable, Sendable, Equatable {
    let absent: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        absent = try container.decode(Bool.self, forKey: .absent)
        guard absent else {
            throw DecodingError.dataCorruptedError(
                forKey: .absent,
                in: container,
                debugDescription: "messageFeedback/delete success requires absent=true"
            )
        }
    }

    private enum CodingKeys: String, CodingKey { case absent }
}

enum RemoteMessageFeedbackFailure: Codable, Sendable, Equatable {
    case sessionNotFound(sessionID: String)
    case targetNotFound(sessionID: String, messageID: String)
    case versionConflict(current: RemoteMessageFeedbackItem?)
    case noteBlank
    case noteTooLarge(maxBytes: Int, actualBytes: Int)

    private enum CodingKeys: String, CodingKey {
        case code, sessionId, messageId, current, maxBytes, actualBytes
    }

    private enum Code: String, Codable {
        case sessionNotFound = "session-not-found"
        case targetNotFound = "target-not-found"
        case versionConflict = "version-conflict"
        case noteBlank = "note-blank"
        case noteTooLarge = "note-too-large"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Code.self, forKey: .code) {
        case .sessionNotFound:
            self = .sessionNotFound(sessionID: try container.decode(String.self, forKey: .sessionId))
        case .targetNotFound:
            self = .targetNotFound(
                sessionID: try container.decode(String.self, forKey: .sessionId),
                messageID: try container.decode(String.self, forKey: .messageId)
            )
        case .versionConflict:
            self = .versionConflict(current: try container.decodeIfPresent(RemoteMessageFeedbackItem.self, forKey: .current))
        case .noteBlank:
            self = .noteBlank
        case .noteTooLarge:
            self = .noteTooLarge(
                maxBytes: try container.decode(Int.self, forKey: .maxBytes),
                actualBytes: try container.decode(Int.self, forKey: .actualBytes)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sessionNotFound(sessionID):
            try container.encode(Code.sessionNotFound, forKey: .code)
            try container.encode(sessionID, forKey: .sessionId)
        case let .targetNotFound(sessionID, messageID):
            try container.encode(Code.targetNotFound, forKey: .code)
            try container.encode(sessionID, forKey: .sessionId)
            try container.encode(messageID, forKey: .messageId)
        case let .versionConflict(current):
            try container.encode(Code.versionConflict, forKey: .code)
            if let current {
                try container.encode(current, forKey: .current)
            } else {
                try container.encodeNil(forKey: .current)
            }
        case .noteBlank:
            try container.encode(Code.noteBlank, forKey: .code)
        case let .noteTooLarge(maxBytes, actualBytes):
            try container.encode(Code.noteTooLarge, forKey: .code)
            try container.encode(maxBytes, forKey: .maxBytes)
            try container.encode(actualBytes, forKey: .actualBytes)
        }
    }
}

enum RemoteMessageFeedbackResult<Value>: Codable, Sendable, Equatable
where Value: Codable & Sendable & Equatable {
    case success(Value)
    case rejected(RemoteMessageFeedbackFailure)

    private enum CodingKeys: String, CodingKey { case ok, value, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .ok) {
            guard !container.contains(.error) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .error,
                    in: container,
                    debugDescription: "message feedback success must not include error"
                )
            }
            self = .success(try container.decode(Value.self, forKey: .value))
        } else {
            guard !container.contains(.value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "message feedback rejection must not include value"
                )
            }
            self = .rejected(try container.decode(RemoteMessageFeedbackFailure.self, forKey: .error))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .success(value):
            try container.encode(true, forKey: .ok)
            try container.encode(value, forKey: .value)
        case let .rejected(error):
            try container.encode(false, forKey: .ok)
            try container.encode(error, forKey: .error)
        }
    }
}

typealias RemoteMessageFeedbackListResult = RemoteMessageFeedbackResult<RemoteMessageFeedbackListValue>
typealias RemoteMessageFeedbackPutResult = RemoteMessageFeedbackResult<RemoteMessageFeedbackItem>
typealias RemoteMessageFeedbackDeleteResult = RemoteMessageFeedbackResult<RemoteMessageFeedbackDeleteValue>

struct MessageFeedbackController: MessageFeedbackControllerAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func list(sessionID: String) async throws -> RemoteMessageFeedbackListResult {
        let result: RemoteMessageFeedbackListResult = try await remote.call(
            RemoteProcedure("messageFeedback/list"),
            arguments: RequestArguments(request: ListRequest(sessionId: sessionID))
        )
        if case let .rejected(error) = result,
           case .sessionNotFound = error {
            return result
        }
        if case .rejected = result {
            throw RemoteConnectionError.protocolViolation("messageFeedback/list returned an unsupported failure")
        }
        return result
    }

    func put(_ request: RemoteMessageFeedbackPutRequest) async throws -> RemoteMessageFeedbackPutResult {
        try await remote.call(
            RemoteProcedure("messageFeedback/put"),
            arguments: RequestArguments(request: request)
        )
    }

    func delete(_ request: RemoteMessageFeedbackDeleteRequest) async throws -> RemoteMessageFeedbackDeleteResult {
        let result: RemoteMessageFeedbackDeleteResult = try await remote.call(
            RemoteProcedure("messageFeedback/delete"),
            arguments: RequestArguments(request: request)
        )
        if case let .rejected(error) = result {
            switch error {
            case .sessionNotFound, .versionConflict:
                return result
            default:
                throw RemoteConnectionError.protocolViolation("messageFeedback/delete returned an unsupported failure")
            }
        }
        return result
    }

    private struct ListRequest: Codable, Sendable {
        let sessionId: String
    }

    private struct RequestArguments<Request: Codable & Sendable>: Codable, Sendable {
        let request: Request
    }
}
