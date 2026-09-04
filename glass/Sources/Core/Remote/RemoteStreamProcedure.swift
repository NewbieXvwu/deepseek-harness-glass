import Foundation

struct RemoteStreamProcedure<Arguments: Encodable & Sendable, Frame: Decodable & Sendable>: Sendable {
    let endpoint: String

    init(_ endpoint: String) {
        self.endpoint = endpoint
    }
}
