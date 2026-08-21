import Foundation
import XCTest

@testable import GlassCore

final class NativeImageAttachmentAdmissionTests: XCTestCase {
    func testImageUTIComesFromContentRatherThanFilenameExtension() throws {
        let url = try writeFixture(data: onePixelPNG, suffix: ".not-an-image")
        let result = NativeImageAttachmentAdmission.admit(
            url: url,
            limits: limits(),
            existingImageCount: 0,
            existingImageBytes: 0
        )

        guard case let .success(image) = result else {
            return XCTFail("a valid PNG magic header must not be rejected because of its filename")
        }
        XCTAssertEqual(image.mediaType, "image/png")
        XCTAssertEqual(image.pixelWidth, 1)
        XCTAssertEqual(image.pixelHeight, 1)
    }

    func testSpoofedPNGExtensionWithNonImageContentIsRejected() throws {
        let url = try writeFixture(data: Data("not an image".utf8), suffix: ".png")
        XCTAssertEqual(
            NativeImageAttachmentAdmission.admit(
                url: url,
                limits: limits(),
                existingImageCount: 0,
                existingImageBytes: 0
            ),
            .failure(.unsupportedContentType)
        )
    }

    func testAdmissionFailsClosedWithoutHostLimitsAndBeforeOversizedRead() throws {
        let url = try writeFixture(data: onePixelPNG, suffix: ".png")
        XCTAssertEqual(
            NativeImageAttachmentAdmission.admit(
                url: url,
                limits: nil,
                existingImageCount: 0,
                existingImageBytes: 0
            ),
            .failure(.limitsUnavailable)
        )
        XCTAssertEqual(
            NativeImageAttachmentAdmission.admit(
                url: url,
                limits: limits(maxImageBytes: onePixelPNG.count - 1),
                existingImageCount: 0,
                existingImageBytes: 0
            ),
            .failure(.fileTooLarge)
        )
    }

    func testAdmissionEnforcesCountMessageBytesDimensionsAndPixels() throws {
        let url = try writeFixture(data: onePixelPNG, suffix: ".png")
        XCTAssertEqual(
            NativeImageAttachmentAdmission.admit(
                url: url,
                limits: limits(),
                existingImageCount: 2,
                existingImageBytes: 0
            ),
            .failure(.tooManyImages)
        )
        XCTAssertEqual(
            NativeImageAttachmentAdmission.admit(
                url: url,
                limits: limits(maxMessageImageBytes: onePixelPNG.count - 1),
                existingImageCount: 0,
                existingImageBytes: 0
            ),
            .failure(.messageTooLarge)
        )
        XCTAssertEqual(
            NativeImageAttachmentAdmission.admit(
                url: url,
                limits: limits(maxImageDimension: 0),
                existingImageCount: 0,
                existingImageBytes: 0
            ),
            .failure(.dimensionsExceeded)
        )
        XCTAssertEqual(
            NativeImageAttachmentAdmission.admit(
                url: url,
                limits: limits(maxImagePixels: 0),
                existingImageCount: 0,
                existingImageBytes: 0
            ),
            .failure(.pixelsExceeded)
        )
    }

    private func limits(
        maxImageBytes: Int = 4_096,
        maxImagesPerMessage: Int = 2,
        maxMessageImageBytes: Int = 8_192,
        maxImagePixels: Int = 16,
        maxImageDimension: Int = 4,
        mediaTypes: [String] = ["image/png"]
    ) -> ImageAttachmentLimits {
        .init(
            maxImageBytes: maxImageBytes,
            maxImagesPerMessage: maxImagesPerMessage,
            maxMessageImageBytes: maxMessageImageBytes,
            maxImagePixels: maxImagePixels,
            maxImageDimension: maxImageDimension,
            mediaTypes: mediaTypes
        )
    }

    private func writeFixture(data: Data, suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(suffix.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        try data.write(to: url, options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9UQAAAABJRU5ErkJggg==")!
}
