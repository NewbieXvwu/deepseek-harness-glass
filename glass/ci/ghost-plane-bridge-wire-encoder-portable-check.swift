import Foundation

@main
struct GhostPlaneBridgeWireEncoderPortableCheck {
    static func main() throws {
        let message = GhostPlaneBridgeMessage(
            documentEpoch: 1,
            sequence: 2,
            direction: .nativeToPlane,
            event: .keyboard(.init(phase: .down, key: "Enter", code: "Enter", location: 0, modifiers: [.command], isRepeat: false, isComposing: false))
        )
        let roundTrip = try GhostPlaneBridgeWireDecoder.decode(GhostPlaneBridgeWireEncoder.encode(message))
        precondition(roundTrip == message)
    }
}
