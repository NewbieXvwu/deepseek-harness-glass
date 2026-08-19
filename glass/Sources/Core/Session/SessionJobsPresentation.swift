import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Pure presentation ordering for Host `session/jobs` whole snapshots.
/// Mirrors the locked official Jobs action: live jobs first in start order, then
/// settled jobs newest-first with start time as a deterministic tie-breaker.
enum SessionJobsPresentation {
    static func isLive(_ job: NativeSessionStore.BackgroundJob) -> Bool {
        job.status == .running || job.status == .stopping
    }

    static func ordered(_ jobs: [NativeSessionStore.BackgroundJob]) -> [NativeSessionStore.BackgroundJob] {
        jobs.sorted { left, right in
            let leftLive = isLive(left)
            let rightLive = isLive(right)
            if leftLive != rightLive { return leftLive }
            if leftLive { return left.startedAt < right.startedAt }
            let leftFinished = left.finishedAt ?? left.startedAt
            let rightFinished = right.finishedAt ?? right.startedAt
            if leftFinished != rightFinished { return leftFinished > rightFinished }
            return left.startedAt < right.startedAt
        }
    }

    static func elapsedMilliseconds(for job: NativeSessionStore.BackgroundJob, now: Int) -> Int {
        max(0, (isLive(job) ? now : (job.finishedAt ?? job.startedAt)) - job.startedAt)
    }
}
