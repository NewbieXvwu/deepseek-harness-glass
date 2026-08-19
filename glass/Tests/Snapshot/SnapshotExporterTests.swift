import AppKit
import XCTest
@testable import GlassSnapshot

@MainActor
final class SnapshotExporterTests: XCTestCase {
    func testRejectsAllBlackCompositorFrame() throws {
        let bitmap = try makeBitmap()

        XCTAssertFalse(SnapshotExporter.hasVisibleSDRContent(bitmap))
    }

    func testAcceptsCompositorFrameWithVisibleSDRContent() throws {
        let bitmap = try makeBitmap()
        guard let data = bitmap.bitmapData else {
            XCTFail("Expected bitmap storage")
            return
        }
        data[0] = 32

        XCTAssertTrue(SnapshotExporter.hasVisibleSDRContent(bitmap))
    }

    private func makeBitmap() throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 48,
            pixelsHigh: 48,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotTestError.cannotAllocateBitmap
        }
        guard let data = bitmap.bitmapData else {
            throw SnapshotTestError.missingBitmapStorage
        }
        for index in 0..<(bitmap.bytesPerRow * bitmap.pixelsHigh) {
            data[index] = 0
        }
        return bitmap
    }

    private enum SnapshotTestError: Error {
        case cannotAllocateBitmap
        case missingBitmapStorage
    }
}
