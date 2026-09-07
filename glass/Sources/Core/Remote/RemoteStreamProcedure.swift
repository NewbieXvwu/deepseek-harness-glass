import Foundation

struct RemoteStreamProcedure<Arguments: Encodable & Sendable, Frame: Decodable & Sendable>: Sendable {
    let endpoint: RemoteEndpoint

    init(_ endpoint: RemoteEndpoint) {
        self.endpoint = endpoint
    }
}
