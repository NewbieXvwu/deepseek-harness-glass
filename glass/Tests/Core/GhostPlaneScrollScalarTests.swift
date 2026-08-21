@testable import GlassCore
import XCTest

final class GhostPlaneScrollScalarTests: XCTestCase {
    func testAppliesStrictlyIncreasingCurrentDocumentSamples() {
        var synchronizer = GhostPlaneScrollSynchronizer(documentEpoch: 17)

        XCTAssertEqual(
            synchronizer.receive(sequence: 1, scrollOffset: 0, documentEpoch: 17),
            .applied(.init(documentEpoch: 17, sequence: 1, scrollOffset: 0))
        )
        XCTAssertEqual(
            synchronizer.receive(sequence: 2, scrollOffset: 184.5, documentEpoch: 17),
            .applied(.init(documentEpoch: 17, sequence: 2, scrollOffset: 184.5))
        )
        XCTAssertEqual(
            synchronizer.lastApplied,
            .init(documentEpoch: 17, sequence: 2, scrollOffset: 184.5)
        )
    }

    func testRejectsStaleEpochAndSequenceWithoutMovingLatestAuthority() {
        var synchronizer = GhostPlaneScrollSynchronizer(documentEpoch: 17)
        _ = synchronizer.receive(sequence: 8, scrollOffset: 80, documentEpoch: 17)

        XCTAssertEqual(
            synchronizer.receive(sequence: 9, scrollOffset: 90, documentEpoch: 16),
            .ignoredStaleEpoch(expected: 17, received: 16)
        )
        XCTAssertEqual(
            synchronizer.receive(sequence: 8, scrollOffset: 800, documentEpoch: 17),
            .ignoredStaleSequence(lastApplied: 8, received: 8)
        )
        XCTAssertEqual(
            synchronizer.receive(sequence: 7, scrollOffset: 700, documentEpoch: 17),
            .ignoredStaleSequence(lastApplied: 8, received: 7)
        )
        XCTAssertEqual(synchronizer.lastApplied, .init(documentEpoch: 17, sequence: 8, scrollOffset: 80))
    }

    func testPreservesElasticSignedOffsetButRejectsNonFiniteValues() {
        var synchronizer = GhostPlaneScrollSynchronizer(documentEpoch: 2)

        XCTAssertEqual(
            synchronizer.receive(sequence: 1, scrollOffset: -14.25, documentEpoch: 2),
            .applied(.init(documentEpoch: 2, sequence: 1, scrollOffset: -14.25))
        )
        XCTAssertEqual(
            synchronizer.lastApplied?.translationY,
            14.25
        )
        XCTAssertEqual(
            synchronizer.receive(sequence: 2, scrollOffset: .infinity, documentEpoch: 2),
            .rejectedNonFiniteOffset
        )
        XCTAssertEqual(
            synchronizer.receive(sequence: 3, scrollOffset: .nan, documentEpoch: 2),
            .rejectedNonFiniteOffset
        )
        XCTAssertEqual(synchronizer.lastApplied, .init(documentEpoch: 2, sequence: 1, scrollOffset: -14.25))
    }

    func testRendererArgumentsArePrimitiveAndDoNotContainTransformSource() {
        let scalar = GhostPlaneScrollScalar(documentEpoch: 4, sequence: 9, scrollOffset: 33.5)

        XCTAssertEqual(scalar.rendererArguments, ["scrollOffset": 33.5])
        XCTAssertFalse(scalar.rendererArguments.keys.contains("javascript"))
        XCTAssertFalse(scalar.rendererArguments.keys.contains("css"))
    }
}
