import Foundation

@main
struct GhostPlaneScrollScalarPortableCheck {
    static func main() throws {
        var synchronizer = GhostPlaneScrollSynchronizer(documentEpoch: 17)
        try equal(
            synchronizer.receive(sequence: 1, scrollOffset: 0, documentEpoch: 17),
            .applied(.init(documentEpoch: 17, sequence: 1, scrollOffset: 0)),
            "initial current-document scroll sample"
        )
        try equal(
            synchronizer.receive(sequence: 2, scrollOffset: 184.5, documentEpoch: 17),
            .applied(.init(documentEpoch: 17, sequence: 2, scrollOffset: 184.5)),
            "strictly later scroll sample"
        )
        try equal(
            synchronizer.receive(sequence: 3, scrollOffset: 300, documentEpoch: 16),
            .ignoredStaleEpoch(expected: 17, received: 16),
            "stale document epoch"
        )
        try equal(
            synchronizer.receive(sequence: 2, scrollOffset: 999, documentEpoch: 17),
            .ignoredStaleSequence(lastApplied: 2, received: 2),
            "replayed source sequence"
        )
        try equal(
            synchronizer.lastApplied,
            .init(documentEpoch: 17, sequence: 2, scrollOffset: 184.5),
            "stale samples must preserve newest authority"
        )

        var elastic = GhostPlaneScrollSynchronizer(documentEpoch: 2)
        try equal(
            elastic.receive(sequence: 1, scrollOffset: -14.25, documentEpoch: 2),
            .applied(.init(documentEpoch: 2, sequence: 1, scrollOffset: -14.25)),
            "elastic signed offset"
        )
        try equal(elastic.lastApplied?.translationY, 14.25, "translation sign")
        try equal(
            elastic.receive(sequence: 2, scrollOffset: .infinity, documentEpoch: 2),
            .rejectedNonFiniteOffset,
            "infinite offset"
        )
        try equal(
            elastic.receive(sequence: 3, scrollOffset: .nan, documentEpoch: 2),
            .rejectedNonFiniteOffset,
            "NaN offset"
        )
        let scalar = GhostPlaneScrollScalar(documentEpoch: 2, sequence: 1, scrollOffset: -14.25)
        try equal(scalar.rendererArguments, ["scrollOffset": -14.25], "primitive renderer argument")

        print("ghost plane scroll scalar portable check passed")
    }

    private static func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw CheckFailure("\(label): expected \(expected), got \(actual)")
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
