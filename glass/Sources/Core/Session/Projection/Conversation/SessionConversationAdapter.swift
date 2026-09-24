import Foundation

extension ConversationEventInput {
    init(remoteRecord: RemoteSessionHistoryRecord) {
        self.init(remoteEvent: remoteRecord.event)
    }

    init(remoteEvent: RemoteSessionWireEvent) {
        self.init(event: SessionEventDTO(
            type: remoteEvent.type,
            seq: remoteEvent.seq.rawValue,
            time: Double(remoteEvent.time),
            data: remoteEvent.data,
            surfaceOp: remoteEvent.surfaceOp,
            sourceEventSeqs: remoteEvent.sourceEventSeqs,
            ignorable: remoteEvent.ignorable
        ))
    }
}
