import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native counterpart of the official session-header Jobs action. It consumes
/// only the Host's `session/jobs` whole snapshot and hides entirely when empty.
struct NativeJobsHeaderAction: View {
    let jobs: [NativeSessionStore.BackgroundJob]
    @State private var open = false
    @State private var nowMilliseconds = Int(Date().timeIntervalSince1970 * 1_000)

    private var orderedJobs: [NativeSessionStore.BackgroundJob] { SessionJobsPresentation.ordered(jobs) }
    private var liveCount: Int { jobs.filter(SessionJobsPresentation.isLive).count }

    var body: some View {
        if !jobs.isEmpty {
            Button(action: { open.toggle(); nowMilliseconds = Int(Date().timeIntervalSince1970 * 1_000) }) {
                HStack(spacing: OfficialUISpec.Spacing.p6) {
                    Circle().fill(liveCount > 0 ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.caption)
                        .frame(width: 6, height: 6)
                    Text(countLabel)
                        .font(OfficialUISpec.Typography.xs13)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(countLabel)
            .popover(isPresented: $open, arrowEdge: .bottom) { menu }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                if open && liveCount > 0 { nowMilliseconds = Int(Date().timeIntervalSince1970 * 1_000) }
            }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            ForEach(orderedJobs) { job in
                HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p8) {
                    Circle().fill(statusColor(job.status)).frame(width: 7, height: 7)
                    Text(job.kind).font(OfficialUISpec.Typography.xs13).foregroundStyle(OfficialUISpec.Token.secondary)
                    Text(job.label).font(OfficialUISpec.Typography.xs13).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(job.detail ?? statusLabel(job.status)).font(OfficialUISpec.Typography.xs13).foregroundStyle(OfficialUISpec.Token.caption)
                    Text(duration(for: job)).font(OfficialUISpec.Typography.xs13).foregroundStyle(OfficialUISpec.Token.caption)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(OfficialUISpec.Spacing.p12)
        .frame(minWidth: 300, maxWidth: 460, alignment: .leading)
    }

    private var countLabel: String {
        let count = liveCount > 0 ? liveCount : jobs.count
        let key = liveCount > 0 ? (count == 1 ? "count.live.one" : "count.live.other") : (count == 1 ? "count.idle.one" : "count.idle.other")
        return template(key, replacements: ["count": String(count)])
    }

    private func duration(for job: NativeSessionStore.BackgroundJob) -> String {
        let seconds = SessionJobsPresentation.elapsedMilliseconds(for: job, now: nowMilliseconds) / 1_000
        let hours = seconds / 3_600, minutes = (seconds / 60) % 60, remainder = seconds % 60
        if hours > 0 { return template("duration.hours", replacements: ["hours": String(hours), "minutes": String(minutes)]) }
        if minutes > 0 { return template("duration.minutes", replacements: ["minutes": String(minutes), "seconds": String(remainder)]) }
        return template("duration.seconds", replacements: ["seconds": String(remainder)])
    }

    private func statusLabel(_ status: NativeSessionStore.BackgroundJob.Status) -> String { template("status.\(status.rawValue)") }
    private func template(_ key: String, replacements: [String: String] = [:]) -> String {
        let language = Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"
        var value = OfficialUISpec.LocaleCatalog.value(namespace: "ui-jobs", key: key, language: language) ?? key
        for (token, replacement) in replacements { value = value.replacingOccurrences(of: "{\(token)}", with: replacement) }
        return value
    }
    private func statusColor(_ status: NativeSessionStore.BackgroundJob.Status) -> Color {
        switch status { case .running: OfficialUISpec.Token.businessBlue; case .stopping, .killed: OfficialUISpec.Token.warningPrimary; case .completed: OfficialUISpec.Token.success; case .failed: OfficialUISpec.Token.errorPrimary }
    }
}
