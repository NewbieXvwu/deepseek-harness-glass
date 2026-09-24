import XCTest

@testable import GlassCore

final class RemoteMuxConnectionTests: XCTestCase {
    private struct Item: Decodable, Equatable {
        let name: String
    }

    private struct BrokenMessage: Encodable {
        func encode(to encoder: Encoder) throws {
            throw BrokenEncoding.expected
        }
    }

    private enum BrokenEncoding: Error {
        case expected
    }

    func testItemDecodeFailureIsProtocolViolation() {
        let data = Data(#"{"type":"item","streamId":"stream-1","value":{"name":1}}"#.utf8)

        XCTAssertThrowsError(try RemoteMuxConnection.decodeItem(Item.self, data: data)) { error in
            guard case let RemoteConnectionError.protocolViolation(message) = error else {
                return XCTFail("expected protocolViolation, got \(error)")
            }
            XCTAssertTrue(message.contains("invalid Remote stream item value"))
        }
    }

    func testMissingItemValueIsProtocolViolation() {
        let data = Data(#"{"type":"item","streamId":"stream-1"}"#.utf8)

        XCTAssertThrowsError(try RemoteMuxConnection.decodeItem(Item.self, data: data)) { error in
            XCTAssertEqual(
                error as? RemoteConnectionError,
                .protocolViolation("Remote stream item omitted value")
            )
        }
    }

    func testMessageEncodeFailureIsProtocolViolation() {
        XCTAssertThrowsError(try RemoteMuxConnection.encodeMessage(BrokenMessage())) { error in
            guard case let RemoteConnectionError.protocolViolation(message) = error else {
                return XCTFail("expected protocolViolation, got \(error)")
            }
            XCTAssertTrue(message.contains("failed to encode Remote stream message"))
        }
    }

    func testValidItemStillDecodes() throws {
        let data = Data(#"{"type":"item","streamId":"stream-1","value":{"name":"ok"}}"#.utf8)

        XCTAssertEqual(
            try RemoteMuxConnection.decodeItem(Item.self, data: data),
            Item(name: "ok")
        )
    }
}
