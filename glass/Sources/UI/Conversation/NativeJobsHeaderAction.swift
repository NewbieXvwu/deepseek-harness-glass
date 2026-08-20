import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native counterpart of the official session-header Jobs action. It consumes
/// only the Host's `session/jobs` whole snapshot and hides entirely when empty.
struct NativeJobsHeaderAction: View {
    let jobs: [NativeSessionStore.BackgroundJob]
    /// Used solely by SnapshotExporter to capture the official expanded state.
    let initiallyOpen: Bool
    @State private var open: Bool
    @State private var nowMilliseconds = Int(Date().timeIntervalSince1970 * 1_000)

    init(jobs: [NativeSessionStore.BackgroundJob], initiallyOpen: Bool = false) {
        self.jobs = jobs
        self.initiallyOpen = initiallyOpen
        _open = State(initialValue: initiallyOpen)
    }

    private var orderedJobs: [NativeSessionStore.BackgroundJob] { SessionJobsPresentation.ordered(jobs) }
    private var liveCount: Int { jobs.filter(SessionJobsPresentation.isLive).count }

    var body: some View {
        if !jobs.isEmpty {
            Button(action: { open.toggle(); nowMilliseconds = Int(Date().timeIntervalSince1970 * 1_000) }) {
                HStack(spacing: 3) {
                    Circle().fill(liveCount > 0 ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.caption)
                        .frame(width: 6, height: 6)
                    Text(countLabel)
                        .font(.system(size: 12))
                        .padding(.horizontal, 5)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 2)
                .frame(minHeight: 28)
                .foregroundStyle(OfficialUISpec.Token.caption)
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
        VStack(alignment: .leading, spacing: 1) {
            ForEach(orderedJobs) { job in
                HStack(spacing: 8) {
                    Circle().fill(statusColor(job.status)).frame(width: 7, height: 7)
                    Text(job.kind)
                        .font(.system(size: 11))
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .padding(.horizontal, 6)
                        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(job.label)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(job.detail ?? statusLabel(job.status))
                        .font(.system(size: 11))
                        .foregroundStyle(OfficialUISpec.Token.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 134, alignment: .trailing)
                    Text(duration(for: job))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(OfficialUISpec.Token.caption)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
                .foregroundStyle(SessionJobsPresentation.isLive(job) ? OfficialUISpec.Token.primary : OfficialUISpec.Token.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(4)
        .frame(width: 336, alignment: .leading)
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
