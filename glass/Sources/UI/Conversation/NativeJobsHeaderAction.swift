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
    /// Window-local override for a capture contract; production derives this
    /// from the current system locale through the same official catalog.
    let languageCode: String?
    @State private var open: Bool
    @State private var nowMilliseconds = Int(Date().timeIntervalSince1970 * 1_000)

    init(
        jobs: [NativeSessionStore.BackgroundJob],
        initiallyOpen: Bool = false,
        languageCode: String? = nil
    ) {
        self.jobs = jobs
        self.initiallyOpen = initiallyOpen
        self.languageCode = languageCode
        _open = State(initialValue: initiallyOpen)
    }

    static func resolvedLanguageCode(override: String?, current: String?) -> String {
        if override == "zh" { return "zh" }
        if override == "en" { return "en" }
        return current == "zh" ? "zh" : "en"
    }

    private var orderedJobs: [NativeSessionStore.BackgroundJob] { SessionJobsPresentation.ordered(jobs) }
    private var liveCount: Int { jobs.filter(SessionJobsPresentation.isLive).count }

    var body: some View {
        if !jobs.isEmpty {
            Button(action: { open.toggle(); nowMilliseconds = Int(Date().timeIntervalSince1970 * 1_000) }) {
                HStack(spacing: OfficialUISpec.Spacing.p3) {
                    if liveCount > 0 {
                        NativeStateDot(state: .ongoing)
                    }
                    Text(countLabel)
                        .font(OfficialUISpec.Typography.xxs12)
                        .padding(.horizontal, OfficialUISpec.Spacing.p5)
                    Image(systemName: "chevron.down")
                        .font(OfficialUISpec.Typography.xxxsStrong11)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.vertical, OfficialUISpec.Spacing.p3)
                .padding(.horizontal, OfficialUISpec.Spacing.p2)
                .frame(minHeight: OfficialUISpec.Geometry.px28)
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
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p1) {
            ForEach(orderedJobs) { job in
                HStack(spacing: OfficialUISpec.Spacing.p8) {
                    NativeStateDot(state: stateDotState(job.status))
                    Text(job.kind)
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .padding(.horizontal, OfficialUISpec.Spacing.p6)
                        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r5, style: .continuous))
                    Text(job.label)
                        .font(OfficialUISpec.Typography.xs13.monospaced())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(job.detail ?? statusLabel(job.status))
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: OfficialUISpec.Layout.jobsStatusMaximumWidth, alignment: .trailing)
                    Text(duration(for: job))
                        .font(OfficialUISpec.Typography.xxxs11.monospaced())
                        .foregroundStyle(OfficialUISpec.Token.caption)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, OfficialUISpec.Spacing.p6)
                .padding(.horizontal, OfficialUISpec.Spacing.p8)
                .frame(minHeight: OfficialUISpec.Geometry.px32)
                .foregroundStyle(SessionJobsPresentation.isLive(job) ? OfficialUISpec.Token.primary : OfficialUISpec.Token.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(OfficialUISpec.Spacing.p4)
        .frame(width: OfficialUISpec.Geometry.px336, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(template("list.aria"))
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
        Self.localizedValue(
            key: key,
            language: Self.resolvedLanguageCode(
                override: languageCode,
                current: Locale.current.language.languageCode?.identifier
            ),
            replacements: replacements
        )
    }

    /// Locked `ui-jobs` locale lookup shared by the native renderer and its
    /// App regression. An unknown key fails closed to the key, matching the
    /// existing catalog fallback rather than inventing product copy.
    static func localizedValue(
        key: String,
        language: String,
        replacements: [String: String] = [:]
    ) -> String {
        var value = OfficialUISpec.LocaleCatalog.value(namespace: "ui-jobs", key: key, language: language) ?? key
        for (token, replacement) in replacements { value = value.replacingOccurrences(of: "{\(token)}", with: replacement) }
        return value
    }
    private func stateDotState(_ status: NativeSessionStore.BackgroundJob.Status) -> NativeStateDot.State {
        switch status {
        case .running:
            .ongoing
        case .stopping, .killed:
            .warning
        case .completed:
            .done
        case .failed:
            .error
        }
    }
}
