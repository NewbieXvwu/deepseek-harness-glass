/// Pure presentation contract for the transcript's Host-owned running tail.
/// A local streaming delta never creates a second status identity; only the
/// reducer's `isRunning` authority controls this fixed anchor.
enum NativeTranscriptTailPresentation {
    static let runningStatusID = "running-turn-status"

    static func showsRunningStatus(isRunning: Bool) -> Bool {
        isRunning
    }

    static func scrollTarget(isRunning: Bool, durableTailID: String?) -> String? {
        isRunning ? runningStatusID : durableTailID
    }
}
