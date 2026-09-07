import Foundation

enum RemoteJSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RemoteJSONValue])
    case object([String: RemoteJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([RemoteJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: RemoteJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

struct RemoteFailurePayload: Codable, Sendable, Equatable {
    let code: String
    let message: String
    let details: [String: RemoteJSONValue]
}

private struct RemoteClientRequest<Arguments: Encodable>: Encodable {
    let type = "client-request"
    let rpcId: String
    let method: String
    let payload: Payload

    struct Payload: Encodable {
        let args: Arguments
    }
}

private struct RemoteServerResponse<Output: Decodable>: Decodable {
    let type: String
    let rpcId: String
    let result: ResultPayload

    enum ResultPayload: Decodable {
        case value(Output)
        case failure(RemoteFailurePayload)

        private enum CodingKeys: String, CodingKey { case ok, value, error }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if try container.decode(Bool.self, forKey: .ok) {
                self = .value(try container.decode(Output.self, forKey: .value))
            } else {
                self = .failure(try container.decode(RemoteFailurePayload.self, forKey: .error))
            }
        }
    }
}

enum RemoteDecodedResult<Output: Sendable>: Sendable {
    case value(Output)
    case failure(RemoteFailurePayload)
}

private struct RemoteServerNoValueResponse: Decodable {
    let type: String
    let rpcId: String
    let result: ResultPayload

    enum ResultPayload: Decodable {
        case success
        case failure(RemoteFailurePayload)

        private enum CodingKeys: String, CodingKey { case ok, error }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if try container.decode(Bool.self, forKey: .ok) {
                self = .success
            } else {
                self = .failure(try container.decode(RemoteFailurePayload.self, forKey: .error))
            }
        }
    }
}

enum RemoteDecodedNoValue: Sendable {
    case success
    case failure(RemoteFailurePayload)
}

enum RemoteWireCodec {
    static func request<Arguments: Encodable>(
        rpcID: String,
        endpoint: String,
        arguments: Arguments,
        encoder: JSONEncoder
    ) throws -> Data {
        try encoder.encode(RemoteClientRequest(
            rpcId: rpcID,
            method: endpoint,
            payload: .init(args: arguments)
        ))
    }

    static func response<Output: Decodable>(
        _ type: Output.Type,
        data: Data,
        decoder: JSONDecoder
    ) throws -> (rpcID: String, result: RemoteDecodedResult<Output>) where Output: Sendable {
        let response = try decoder.decode(RemoteServerResponse<Output>.self, from: data)
        guard response.type == "server-response" else {
            throw RemoteConnectionError.protocolViolation("expected server-response envelope")
        }
        switch response.result {
        case let .value(value): return (response.rpcId, .value(value))
        case let .failure(error): return (response.rpcId, .failure(error))
        }
    }

    static func responseNoValue(
        data: Data,
        decoder: JSONDecoder
    ) throws -> (rpcID: String, result: RemoteDecodedNoValue) {
        let response = try decoder.decode(RemoteServerNoValueResponse.self, from: data)
        guard response.type == "server-response" else {
            throw RemoteConnectionError.protocolViolation("expected server-response envelope")
        }
        switch response.result {
        case .success: return (response.rpcId, .success)
        case let .failure(error): return (response.rpcId, .failure(error))
        }
    }
}
