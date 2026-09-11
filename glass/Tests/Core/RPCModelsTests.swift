import XCTest

@testable import GlassCore
final class RPCModelsTests: XCTestCase {
    func testRemoteErrorTaxonomyKeepsCarrierAndMethodAvailabilityDistinct() {
        XCTAssertEqual(RemoteConnectionError.authenticationRequired.category, .authentication)
        XCTAssertEqual(RemoteConnectionError.carrierLost("offline").category, .carrierLost)
        XCTAssertEqual(RemoteConnectionError.timeout.category, .transport)
        XCTAssertEqual(RemoteConnectionError.httpStatus(404).category, .methodUnavailable)
        XCTAssertEqual(RemoteConnectionError.remote(.init(
            code: "gateway/method-unavailable",
            message: "missing",
            details: [:]
        )).category, .methodUnavailable)
        XCTAssertEqual(RemoteConnectionError.remote(.init(
            code: "workspace/not-found",
            message: "missing",
            details: [:]
        )).category, .remoteBusiness)
        XCTAssertEqual(RemoteConnectionError.protocolViolation("bad frame").category, .protocolViolation)
    }

    func testImageAttachmentLimitsRequireMaximumDimension() throws {
        let source = Data("""
        {
          "maxImageBytes": 1048576,
          "maxImagesPerMessage": 2,
          "maxMessageImageBytes": 2097152,
          "maxImagePixels": 40000000,
          "maxImageDimension": 2000,
          "mediaTypes": ["image/png", "image/jpeg"]
        }
        """.utf8)
        let limits = try JSONDecoder().decode(ImageAttachmentLimits.self, from: source)
        XCTAssertEqual(limits.maxImageDimension, 2000)
        XCTAssertEqual(limits.maxImagesPerMessage, 2)
        XCTAssertEqual(limits.mediaTypes, ["image/png", "image/jpeg"])

        let incomplete = Data("""
        {
          "maxImageBytes": 1048576,
          "maxImagesPerMessage": 2,
          "maxMessageImageBytes": 2097152,
          "maxImagePixels": 40000000,
          "mediaTypes": ["image/png"]
        }
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ImageAttachmentLimits.self, from: incomplete))
    }

}
