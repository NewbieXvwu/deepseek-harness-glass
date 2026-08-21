import XCTest

@testable import GlassCore

final class MessageFeedbackTransportTests: XCTestCase {
    func testPutRequestEncodesExplicitNullForAbsentObservedVersion() throws {
        let request = MessageFeedbackPutRequest(
            sessionId: "session-1",
            messageId: "message-1",
            rating: .positive,
            note: nil,
            ifVersion: nil
        )
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(value?["sessionId"] as? String, "session-1")
        XCTAssertEqual(value?["messageId"] as? String, "message-1")
        XCTAssertEqual(value?["rating"] as? String, "positive")
        XCTAssertTrue(value?["ifVersion"] is NSNull, "RC8 put must carry null to require an absent feedback item")
        XCTAssertNil(value?["note"], "an omitted note preserves the stored explanation")
    }

    func testPutAndDeleteBusinessEnvelopesPreserveAuthoritativeVersions() throws {
        let decoder = JSONDecoder()
        let put = try decoder.decode(MessageFeedbackPutResponse.self, from: Data("""
        {"ok":true,"value":{"messageId":"message-1","rating":"negative","note":"wrong","version":"v2","createdAt":1,"updatedAt":2}}
        """.utf8))
        XCTAssertTrue(put.ok)
        XCTAssertEqual(put.value?.version, "v2")
        XCTAssertEqual(put.value?.rating, .negative)

        let conflict = try decoder.decode(MessageFeedbackPutResponse.self, from: Data("""
        {"ok":false,"error":{"code":"version-conflict","current":{"messageId":"message-1","rating":"positive","version":"v3","createdAt":1,"updatedAt":3}}}
        """.utf8))
        XCTAssertFalse(conflict.ok)
        XCTAssertEqual(conflict.error?.code, "version-conflict")
        XCTAssertEqual(conflict.error?.current?.version, "v3")

        let delete = MessageFeedbackDeleteRequest(sessionId: "session-1", messageId: "message-1", ifVersion: "v3")
        let request = try JSONSerialization.jsonObject(with: JSONEncoder().encode(delete)) as? [String: Any]
        XCTAssertEqual(request?["ifVersion"] as? String, "v3")
    }
}
