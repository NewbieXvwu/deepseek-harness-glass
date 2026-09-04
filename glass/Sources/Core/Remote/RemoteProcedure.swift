import Foundation

struct RemoteProcedure<Arguments: Encodable & Sendable, Output: Decodable & Sendable>: Sendable {
    let endpoint: String
    let timeout: TimeInterval

    init(_ endpoint: String, timeout: TimeInterval = 30) {
        self.endpoint = endpoint
        self.timeout = timeout
    }
}
