import SwiftUI
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// Native generic fallback for the official `tool.call.toolview` seat.
///
/// Sources: `ui-tool/tool/components/ToolRow.tsx` and
/// `ui-tool/tool/models/tool-call-model.ts`. Plugin-specific card interiors
/// intentionally remain outside this fallback until a NativeUIManifest adapter
/// provides a separately reviewed native implementation.
struct NativeToolRow: View {
    let invocation: NativeSessionStore.ToolInvocation
    let selected: Bool
    let openKnownProjectPath: (String) -> Void
    let canOpenProjectPath: Bool
    let inspect: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: OfficialUISpec.Spacing.p0) {
                Button(action: toggleExpandedAndInspect) {
                    HStack(spacing: OfficialUISpec.Spacing.p6) {
                        leading
                            .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
                        Text(title)
                            .font(OfficialUISpec.Typography.s14)
                            .foregroundStyle(OfficialUISpec.Token.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel)
                .accessibilityValue(stateDescription)

                Circle()
                    .fill(OfficialUISpec.Token.caption)
                    .frame(width: OfficialUISpec.Spacing.p2, height: OfficialUISpec.Spacing.p2)
                    .padding(.horizontal, OfficialUISpec.Spacing.p8)

                if let filePath, canOpenProjectPath, !rowFailed {
                    Button(action: { openKnownProjectPath(filePath) }) {
                        Text(summary)
                            .font(OfficialUISpec.Typography.s14)
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                            .underline(true, color: OfficialUISpec.Token.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filePath)
                } else {
                    Button(action: toggleExpandedAndInspect) {
                        Text(summary)
                            .font(OfficialUISpec.Typography.s14)
                            .foregroundStyle(rowFailed ? OfficialUISpec.Token.errorPrimary : OfficialUISpec.Token.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rowAccessibilityLabel)
                    .accessibilityValue(stateDescription)
                }
                Spacer(minLength: 0)
            }

            if expanded {
                if let terminal {
                    NativeTerminalToolCardBody(presentation: terminal)
                } else {
                    let body = NativeToolRowPresentation.body(toolName: invocation.name, arguments: invocation.arguments)
                    VStack(alignment: .leading, spacing: 8) {
                        if let body {
                            Text(body)
                                .font(OfficialUISpec.Typography.codeSmall12)
                                .foregroundStyle(OfficialUISpec.Token.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let output = invocation.output {
                            if body != nil { Divider() }
                            Text(output)
                                .font(OfficialUISpec.Typography.codeSmall12)
                                .foregroundStyle(rowFailed ? OfficialUISpec.Token.errorPrimary : OfficialUISpec.Token.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(OfficialUISpec.Spacing.p10)
                    .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
                }
            }
        }
        .padding(.horizontal, OfficialUISpec.Spacing.p8)
        .padding(.vertical, OfficialUISpec.Spacing.p5)
        .background(selected ? OfficialUISpec.Token.interactiveHover : Color.clear, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r6, style: .continuous))
        .contentShape(Rectangle())
    }

    private func toggleExpandedAndInspect() {
        expanded.toggle()
        inspect()
    }

    private var title: String {
        switch variant {
        case .search: OfficialUISpec.Text.toolSearch
        case .read: OfficialUISpec.Text.toolRead
        case .bash: OfficialUISpec.Text.toolBash
        case .write: OfficialUISpec.Text.toolWrite
        case .edit: OfficialUISpec.Text.toolEdit
        case .code: OfficialUISpec.Text.toolCode
        case .others: OfficialUISpec.Text.toolCall
        }
    }

    private var summary: String {
        NativeToolRowModel.summary(
            toolName: invocation.name,
            arguments: invocation.arguments,
            isGeneric: variant == .others,
            separator: OfficialUISpec.Text.toolSummarySeparator
        )
    }

    private var filePath: String? {
        NativeToolRowModel.filePath(toolName: invocation.name, arguments: invocation.arguments)
    }

    /// `ToolEventView.for` was retained separately by Core. A terminal call is
    /// insufficient once a result arrives: the settled side must itself admit
    /// `card:'terminal'`, otherwise the official generic raw fallback wins.
    private var terminal: NativeTerminalCardPresentation? {
        NativeTerminalCardPresentation.resolve(
            call: invocation.callView?.nativeTerminalView,
            result: invocation.resultView?.nativeTerminalView,
            settled: state != .running
        )
    }

    private var rowAccessibilityLabel: String {
        summary.isEmpty ? title : "\(title) \(summary)"
    }

    private var state: NativeSessionStore.ToolInvocation.State { invocation.state }

    private var rowFailed: Bool {
        state == .failed || terminal?.failed == true
    }

    private var stateDescription: String {
        if terminal?.failed == true { return OfficialUISpec.Text.toolFailed }
        switch state {
        case .running: OfficialUISpec.Text.toolRunning
        case .completed: ""
        case .failed: OfficialUISpec.Text.toolFailed
        case .stopped: OfficialUISpec.Text.toolStopped
        }
    }

    @ViewBuilder
    private var leading: some View {
        if rowFailed {
            Circle().fill(OfficialUISpec.Token.errorPrimary).frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
        } else {
            switch state {
            case .running:
                ProgressView().controlSize(.mini)
            case .failed:
                // `rowFailed` handles this state above; retain the exhaustive
                // state switch so a future enum case cannot silently render.
                Circle().fill(OfficialUISpec.Token.errorPrimary).frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
            case .stopped:
                Circle().fill(OfficialUISpec.Token.warningPrimary).frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
            case .completed:
                OfficialAssetImage(name: iconName, template: true)
                    .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
            }
        }
    }

    private var iconName: String {
        switch variant {
        case .search: "icon-tool-search"
        case .read: "icon-tool-read"
        case .bash: "icon-tool-bash"
        case .write, .edit: "icon-tool-edit"
        case .code: "icon-tool-code"
        case .others: "icon-tool-others"
        }
    }

    private enum Variant {
        case search, read, bash, write, edit, code, others
    }

    private var variant: Variant {
        switch invocation.name {
        case "bash", "pwsh": .bash
        case "read", "web_fetch", "cordis_package_inspect", "cordis_runtime_inspect": .read
        case "web_search", "grep", "glob": .search
        case "write": .write
        case "edit": .edit
        case "run_code": .code
        default: .others
        }
    }
}

/// Native terminal body for the official `card:'terminal'` renderer intent.
///
/// The Host card owns command/output/status facts. This view deliberately has no
/// local card selection and no generic input section: a terminal card replaces
/// the generic body exactly as rc.2 `ToolRow` does. Unknown or mismatched views
/// never construct this body and remain in the safe raw fallback above.
private struct NativeTerminalToolCardBody: View {
    let presentation: NativeTerminalCardPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            if let description = presentation.description, !description.isEmpty {
                Text(description)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(prompt)
                .font(OfficialUISpec.Typography.codeSmall12)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let output = presentation.output {
                Divider()
                Text(output)
                    .font(OfficialUISpec.Typography.codeSmall12)
                    .foregroundStyle(presentation.failed ? OfficialUISpec.Token.errorPrimary : OfficialUISpec.Token.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !presentation.running {
                Divider()
                Text(locale("terminal.noOutput"))
                    .font(OfficialUISpec.Typography.codeSmall12)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
            }
            Text(status)
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(presentation.failed ? OfficialUISpec.Token.errorPrimary : OfficialUISpec.Token.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(OfficialUISpec.Spacing.p10)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
    }

    private var prompt: String {
        let directory = presentation.cwd ?? ""
        return directory.isEmpty ? "$ \(presentation.command)" : "\(directory) $ \(presentation.command)"
    }

    private var status: String {
        if presentation.running { return locale("terminal.running") }
        if let signal = presentation.signal {
            return locale("terminal.signal", replacing: ["signal": signal])
        }
        if let exitCode = presentation.exitCode, exitCode != 0 {
            return locale("terminal.exitCode", replacing: ["code": String(exitCode)])
        }
        return locale("terminal.done")
    }

    private func locale(_ key: String, replacing values: [String: String] = [:]) -> String {
        let template = OfficialUISpec.LocaleCatalog.value(namespace: "ui-conversation", key: key, language: "en") ?? ""
        return values.reduce(template) { partial, replacement in
            partial.replacingOccurrences(of: "{\(replacement.key)}", with: replacement.value)
        }
    }
}

/// Native generic details fallback. It is intentionally text/JSON only until a
/// separately approved native adapter can claim a specific Host `view.card`.
struct NativeToolDetailsBody: View {
    let invocation: NativeSessionStore.ToolInvocation?

    var body: some View {
        Group {
            if let invocation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title(for: invocation.name))
                            .font(OfficialUISpec.Typography.xsStrong13)
                            .foregroundStyle(OfficialUISpec.Token.primary)
                        if invocation.state == .running {
                            Text(OfficialUISpec.Text.toolDetailsRunning)
                                .font(OfficialUISpec.Typography.xs13)
                                .foregroundStyle(OfficialUISpec.Token.secondary)
                        }
                        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
                            Text(invocation.arguments)
                                .font(OfficialUISpec.Typography.codeSmall12)
                                .foregroundStyle(OfficialUISpec.Token.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let output = invocation.output {
                                Divider()
                                Text(output)
                                    .font(OfficialUISpec.Typography.codeSmall12)
                                    .foregroundStyle(invocation.state == .failed ? OfficialUISpec.Token.errorPrimary : OfficialUISpec.Token.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(OfficialUISpec.Spacing.p10)
                        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
                    }
                    .padding(OfficialUISpec.Spacing.p16)
                }
            } else {
                Text(OfficialUISpec.Text.detailsEmpty)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

private extension NativeToolDetailsBody {
    func title(for name: String) -> String {
        switch name {
        case "bash", "pwsh": OfficialUISpec.Text.toolBash
        case "read", "web_fetch", "cordis_package_inspect", "cordis_runtime_inspect": OfficialUISpec.Text.toolRead
        case "web_search", "grep", "glob": OfficialUISpec.Text.toolSearch
        case "write": OfficialUISpec.Text.toolWrite
        case "edit": OfficialUISpec.Text.toolEdit
        case "run_code": OfficialUISpec.Text.toolCode
        default: OfficialUISpec.Text.toolCall
        }
    }
}
