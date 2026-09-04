import Foundation

extension RemoteJSONValue {
    var conversationJSONValue: JSONValue {
        switch self {
        case .null: return .null
        case let .bool(value): return .bool(value)
        case let .number(value): return .number(value)
        case let .string(value): return .string(value)
        case let .array(values): return .array(values.map(\.conversationJSONValue))
        case let .object(values):
            return .object(values.mapValues(\.conversationJSONValue))
        }
    }
}

extension ConversationEventInput {
    init(remoteRecord: RemoteSessionHistoryRecord) {
        self.init(remoteEvent: remoteRecord.event)
    }

    init(remoteEvent: RemoteSessionWireEvent) {
        self.init(event: SessionEventDTO(
            type: remoteEvent.type,
            seq: remoteEvent.seq.rawValue,
            time: Double(remoteEvent.time),
            data: remoteEvent.data.conversationJSONValue,
            surfaceOp: remoteEvent.surfaceOp?.conversationJSONValue,
            sourceEventSeqs: remoteEvent.sourceEventSeqs,
            ignorable: remoteEvent.ignorable
        ))
    }
}
