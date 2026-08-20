import AppKit
import XCTest
@testable import GlassSnapshot

@MainActor
final class SnapshotExporterTests: XCTestCase {
    func testSnapshotColorSchemePinsAppKitAppearance() {
        XCTAssertEqual(SnapshotExporter.lockedAppearanceName(snapshotColorScheme: "dark"), .darkAqua)
        XCTAssertEqual(SnapshotExporter.lockedAppearanceName(snapshotColorScheme: "light"), .aqua)
        XCTAssertEqual(SnapshotExporter.lockedAppearanceName(snapshotColorScheme: nil), .aqua)
        XCTAssertEqual(SnapshotExporter.lockedAppearanceName(snapshotColorScheme: "unsupported"), .aqua)
    }

    func testSnapshotViewportRejectsPostLayoutWidthDrift() {
        let requested = NSSize(width: 1280, height: 840)
        XCTAssertTrue(SnapshotExporter.viewportMatches(requested: requested, actual: requested))
        XCTAssertTrue(SnapshotExporter.viewportMatches(requested: requested, actual: NSSize(width: 1281, height: 839)))
        XCTAssertFalse(SnapshotExporter.viewportMatches(requested: requested, actual: NSSize(width: 1369, height: 840)))
    }

    func testRejectsAllBlackCompositorFrame() throws {
        let bitmap = try makeBitmap()

        XCTAssertFalse(SnapshotExporter.hasVisibleSDRContent(bitmap))
    }

    func testRejectsOpaqueAlphaFirstBlackCompositorFrame() throws {
        let bitmap = try makeBitmap(bitmapFormat: [.alphaFirst])
        guard let data = bitmap.bitmapData else {
            XCTFail("Expected bitmap storage")
            return
        }
        data[0] = .max

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

    func testAcceptsAlphaFirstCompositorFrameWithVisibleSDRContent() throws {
        let bitmap = try makeBitmap(bitmapFormat: [.alphaFirst])
        guard let data = bitmap.bitmapData else {
            XCTFail("Expected bitmap storage")
            return
        }
        data[0] = .max
        data[1] = 32

        XCTAssertTrue(SnapshotExporter.hasVisibleSDRContent(bitmap))
    }

    private func makeBitmap(
        bitmapFormat: NSBitmapImageRep.Format = []
    ) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 48,
            pixelsHigh: 48,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: bitmapFormat,
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
