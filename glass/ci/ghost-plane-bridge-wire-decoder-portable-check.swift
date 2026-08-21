import Foundation

@main
struct GhostPlaneBridgeWireDecoderPortableCheck {
    static func main() throws {
        let message = try GhostPlaneBridgeWireDecoder.decode(Data("""
        {"documentEpoch":3,"sequence":8,"direction":"planeToNative","event":{"kind":"keyboard","phase":"down","key":"Enter","code":"Enter","location":0,"modifiers":1,"isRepeat":false,"isComposing":false}}
        """.utf8))
        precondition(message.documentEpoch == 3 && message.sequence == 8 && message.direction == .planeToNative)
        precondition(message.event == .keyboard(.init(phase: .down, key: "Enter", code: "Enter", location: 0, modifiers: [.shift], isRepeat: false, isComposing: false)))
        do {
            _ = try GhostPlaneBridgeWireDecoder.decode(Data("{\"documentEpoch\":1,\"sequence\":1,\"direction\":\"bad\",\"event\":{\"kind\":\"keyboard\"}}".utf8))
            preconditionFailure("unknown wire direction must reject")
        } catch GhostPlaneBridgeWireDecoder.Rejection.unknownDirection {}
        do {
            _ = try GhostPlaneBridgeWireDecoder.decode(Data("{\"documentEpoch\":1,\"sequence\":1,\"direction\":\"planeToNative\",\"event\":{\"kind\":\"drag\",\"dragPhase\":\"drop\",\"operation\":\"copy\",\"attachmentIDs\":[\"bad\"],\"x\":0,\"y\":0}}".utf8))
            preconditionFailure("invalid UUID must reject")
        } catch GhostPlaneBridgeWireDecoder.Rejection.invalidEvent {}
    }
}
