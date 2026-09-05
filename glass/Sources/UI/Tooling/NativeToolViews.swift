import SwiftUI
import AppKit
import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif
/// Native generic fallback for tool calls without a reviewed native projector.
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
                if let todo, todo.activeExtra > 0 {
                    Button(action: toggleExpandedAndInspect) {
                        Text("+\(todo.activeExtra)")
                            .font(OfficialUISpec.Typography.s14)
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("+\(todo.activeExtra)")
                }
                Spacer(minLength: 0)
            }

            if expanded {
                if let terminal {
                    NativeTerminalToolCardBody(presentation: terminal, maxLines: nil)
                } else if let diff {
                    NativeDiffToolCardBody(presentation: diff, maxLines: 8)
                } else if let read {
                    NativeReadToolCardBody(presentation: read, maxLines: 8)
                } else if let search {
                    NativeSearchToolCardBody(presentation: search, maxLines: 8)
                } else if let web {
                    NativeWebToolCardBody(presentation: web)
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
        if isAskQuestionTool { return conversationLocale("ask.rowTitle") }
        if isTodoTool { return conversationLocale("todo.rowTitle") }
        return switch variant {
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
        if let askQuestion { return askQuestionSummary(askQuestion) }
        if let todo { return todoSummary(todo) }
        return NativeToolRowModel.summary(
            toolName: invocation.name,
            arguments: invocation.arguments,
            isGeneric: variant == .others,
            separator: OfficialUISpec.Text.toolSummarySeparator
        )
    }

    private var isTodoTool: Bool { invocation.name == "todo_write" }
    private var isAskQuestionTool: Bool { invocation.name == "ask_user_question" }

    private var askQuestion: NativeToolAskQuestionPresentation? {
        NativeToolAskQuestionPresentation.resolve(
            toolName: invocation.name,
            isRunning: state == .running,
            isCompleted: state == .completed,
            errorCode: invocation.errorCode,
            textOutput: invocation.textOutput
        )
    }

    private func askQuestionSummary(_ presentation: NativeToolAskQuestionPresentation) -> String {
        switch presentation.summary {
        case .waiting: return conversationLocale("ask.waiting")
        case .cancelled: return conversationLocale("ask.cancelled")
        case .interrupted: return conversationLocale("ask.interrupted")
        case let .answered(answered, total):
            return conversationLocale(
                "ask.answered",
                replacing: ["answered": String(answered), "total": String(total)]
            )
        case .generic:
            return NativeToolRowModel.summary(
                toolName: invocation.name,
                arguments: invocation.arguments,
                isGeneric: variant == .others,
                separator: OfficialUISpec.Text.toolSummarySeparator
            )
        }
    }

    private var todo: NativeToolTodoSummary? {
        NativeToolTodoPresentation.resolve(toolName: invocation.name, arguments: invocation.arguments)
    }

    private func todoSummary(_ todo: NativeToolTodoSummary) -> String {
        let completed = conversationLocale(
            "todo.completed",
            replacing: ["done": String(todo.done), "total": String(todo.total)]
        )
        guard let activeContent = todo.activeContent else { return completed }
        return completed + " · " + activeContent
    }

    private func conversationLocale(_ key: String, replacing values: [String: String] = [:]) -> String {
        let template = OfficialUISpec.LocaleCatalog.value(namespace: "ui-conversation", key: key, language: "en") ?? ""
        return values.reduce(template) { partial, replacement in
            partial.replacingOccurrences(of: "{\(replacement.key)}", with: replacement.value)
        }
    }

    private var filePath: String? {
        NativeToolRowModel.filePath(toolName: invocation.name, arguments: invocation.arguments)
    }

    private var terminal: NativeTerminalCardPresentation? {
        NativeRawToolCardProjector.terminal(invocation)
    }

    private var read: NativeReadCardPresentation? {
        NativeRawToolCardProjector.read(invocation)
    }

    private var diff: NativeDiffCardPresentation? {
        NativeRawToolCardProjector.diff(invocation)
    }

    private var search: NativeSearchCardPresentation? {
        NativeRawToolCardProjector.search(invocation)
    }

    private var web: NativeWebCardPresentation? {
        NativeRawToolCardProjector.web(invocation)
    }

    private var rowAccessibilityLabel: String {
        summary.isEmpty ? title : "\(title) \(summary)"
    }

    private var state: NativeSessionStore.ToolInvocation.State { invocation.state }

    private var effectiveState: NativeSessionStore.ToolInvocation.State {
        askQuestion?.forcesStoppedState == true ? .stopped : state
    }

    private var rowFailed: Bool {
        effectiveState == .failed || terminal?.failed == true
    }

    private var stateDescription: String {
        if terminal?.failed == true { return OfficialUISpec.Text.toolFailed }
        return switch effectiveState {
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
            switch effectiveState {
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
        if isAskQuestionTool { return "icon-question" }
        if isTodoTool { return "icon-checklist" }
        return switch variant {
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
    /// `nil` mirrors ToolRow's uncapped terminal body; details uses 16.
    let maxLines: Int?

    @State private var expanded = false
    @State private var copyFeedback: NativeClipboardCopyFeedback.State = .idle

    private var outputPresentation: NativeTerminalOutputPresentation? {
        NativeTerminalOutputPresentation.resolve(output: presentation.output)
    }

    private var outputWindow: NativeTerminalOutputWindow {
        NativeTerminalOutputWindow.resolve(lines: outputPresentation?.lines ?? [], maxLines: maxLines, expanded: expanded)
    }

    private var ansiWindow: NativeTerminalANSILineWindow {
        NativeTerminalANSILineWindow.resolve(
            lines: outputPresentation?.ansiLines ?? [],
            maxLines: maxLines,
            expanded: expanded
        )
    }

    private var copied: Bool { copyFeedback == .copied }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            if let description = presentation.description, !description.isEmpty {
                Text(description)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p8) {
                NativeStateDot(state: runState)
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                    ForEach(Array(commandLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p8) {
                            Text(index == 0 ? cwdLabel : "$")
                                .foregroundStyle(OfficialUISpec.Token.caption)
                            Text(line)
                                .foregroundStyle(OfficialUISpec.Token.primary)
                        }
                    }
                }
                .font(OfficialUISpec.Typography.codeSmall12)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let terminalStatus {
                    Text(terminalStatus)
                        .font(OfficialUISpec.Typography.xxs12)
                        .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                        .padding(.horizontal, OfficialUISpec.Spacing.p8)
                        .frame(height: OfficialUISpec.Geometry.px22)
                        .background(OfficialUISpec.Token.pillLayer2, in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .accessibilityLabel(status)
            if let output = outputPresentation, !presentation.running, !output.isVisiblyEmpty {
                Divider()
                HStack {
                    Spacer(minLength: 0)
                    Button(action: copyOutput) {
                        Text(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
                            .font(OfficialUISpec.Typography.xs13)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .accessibilityLabel(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                        outputLines(ansiWindow.head)
                        if outputWindow.hiddenCount > 0 {
                            Button(action: { expanded.toggle() }) {
                                Text(expanded
                                     ? locale("terminal.collapseAria")
                                     : locale("terminal.expandRest", replacing: ["n": String(outputWindow.hiddenCount)]))
                                    .font(OfficialUISpec.Typography.codeSmall12)
                                    .foregroundStyle(OfficialUISpec.Token.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(expanded
                                                ? locale("terminal.collapseAria")
                                                : locale("terminal.expandAria", replacing: ["n": String(outputWindow.hiddenCount)]))
                            .accessibilityValue(expanded ? "true" : "false")
                        }
                        outputLines(ansiWindow.tail)
                    }
                    .padding(.vertical, OfficialUISpec.Spacing.p8)
                }
            } else if !presentation.running {
                Divider()
                Text(locale("terminal.noOutput"))
                    .font(OfficialUISpec.Typography.codeSmall12)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
            }
        }
        .padding(OfficialUISpec.Spacing.p10)
        .background(OfficialUISpec.Token.markdownCodeBlock, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
    }

    @ViewBuilder
    private func outputLines(_ lines: [[NativeTerminalANSISpan]]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p0) {
                ForEach(Array(line.enumerated()), id: \.offset) { _, span in
                    NativeTerminalANSISpanText(span: span)
                }
            }
            .font(OfficialUISpec.Typography.codeSmall12)
            .fixedSize(horizontal: true, vertical: false)
            .textSelection(.enabled)
            .frame(minHeight: OfficialUISpec.Geometry.px22, alignment: .leading)
        }
    }

    private func copyOutput() {
        guard NativeClipboardCopyFeedback.acceptsActivation(state: copyFeedback),
              let rawOutput = outputPresentation?.rawOutput
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copyFeedback = NativeClipboardCopyFeedback.resolveWrite(
            state: copyFeedback,
            accepted: pasteboard.setString(rawOutput, forType: .string)
        )
        guard copied else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            copyFeedback = NativeClipboardCopyFeedback.resolveExpiry(state: copyFeedback)
        }
    }

    private var commandLines: [String] {
        let command = presentation.command.hasSuffix("\n")
            ? String(presentation.command.dropLast())
            : presentation.command
        return command.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private var cwdLabel: String {
        guard let cwd = presentation.cwd, !cwd.isEmpty else { return "$" }
        let trimmed = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        guard let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last, !last.isEmpty else {
            return cwd
        }
        return String(last)
    }

    private var runState: NativeStateDot.State {
        if presentation.running { return .ongoing }
        return presentation.failed ? .error : .done
    }

    private var status: String {
        if presentation.running { return locale("terminal.running") }
        return presentation.failed ? locale("terminal.failed") : locale("terminal.done")
    }

    private var terminalStatus: String? {
        if let signal = presentation.signal {
            return locale("terminal.signal", replacing: ["signal": signal])
        }
        if let exitCode = presentation.exitCode, exitCode != 0 {
            return locale("terminal.exitCode", replacing: ["code": String(exitCode)])
        }
        return nil
    }

    private func locale(_ key: String, replacing values: [String: String] = [:]) -> String {
        let template = OfficialUISpec.LocaleCatalog.value(namespace: "ui-conversation", key: key, language: "en") ?? ""
        return values.reduce(template) { partial, replacement in
            partial.replacingOccurrences(of: "{\(replacement.key)}", with: replacement.value)
        }
    }
}

/// SwiftUI renderer for a Foundation-admitted ANSI span. Basic terminal colors
/// use the same official semantic roles as rc.2; palette/truecolor values are
/// Host-authored terminal data and retain their literal RGB appearance.
private struct NativeTerminalANSISpanText: View {
    let span: NativeTerminalANSISpan

    private var style: NativeTerminalANSIStyle { span.style ?? .init() }

    private var text: Text {
        var text = Text(span.text)
        if style.bold { text = text.bold() }
        if style.italic { text = text.italic() }
        if style.underline { text = text.underline() }
        if style.strikethrough { text = text.strikethrough() }
        return text
    }

    var body: some View {
        text
            .foregroundStyle(foreground ?? OfficialUISpec.Token.primary)
            .background(background ?? Color.clear)
            .opacity(style.hidden ? 0 : (style.dim ? 0.7 : 1))
    }

    private var foreground: Color? { color(style.foreground) }
    private var background: Color? { color(style.background) }

    private func color(_ color: NativeTerminalANSIColor?) -> Color? {
        guard let color else { return nil }
        switch color {
        case let .basic(basic):
            switch basic {
            case .black, .white: return OfficialUISpec.Token.primary
            case .brightBlack: return OfficialUISpec.Token.caption
            case .red: return OfficialUISpec.Token.errorPrimary
            case .brightRed: return OfficialUISpec.Token.errorSecondary
            case .green, .brightGreen: return OfficialUISpec.Token.success
            case .yellow: return OfficialUISpec.Token.warningPrimary
            case .brightYellow: return OfficialUISpec.Token.warningBorder
            case .blue, .brightBlue: return OfficialUISpec.Token.businessBlue
            case .magenta: return literal(red: 187, green: 0, blue: 187)
            case .brightMagenta: return literal(red: 255, green: 85, blue: 255)
            case .cyan: return literal(red: 0, green: 187, blue: 187)
            case .brightCyan: return literal(red: 0, green: 255, blue: 255)
            case .brightWhite: return OfficialUISpec.Token.primary
            }
        case let .rgb(red, green, blue):
            return literal(red: red, green: green, blue: blue)
        case let .palette(index):
            return palette(index)
        }
    }

    private func palette(_ index: Int) -> Color {
        let standard: [Color] = [
            literal(red: 0, green: 0, blue: 0), literal(red: 187, green: 0, blue: 0),
            literal(red: 0, green: 187, blue: 0), literal(red: 187, green: 187, blue: 0),
            literal(red: 0, green: 0, blue: 187), literal(red: 187, green: 0, blue: 187),
            literal(red: 0, green: 187, blue: 187), literal(red: 255, green: 255, blue: 255),
            literal(red: 85, green: 85, blue: 85), literal(red: 255, green: 85, blue: 85),
            literal(red: 0, green: 255, blue: 0), literal(red: 255, green: 255, blue: 85),
            literal(red: 85, green: 85, blue: 255), literal(red: 255, green: 85, blue: 255),
            literal(red: 0, green: 255, blue: 255), literal(red: 255, green: 255, blue: 255),
        ]
        if (0..<standard.count).contains(index) { return standard[index] }
        if (16...231).contains(index) {
            let value = index - 16
            let components = [0, 95, 135, 175, 215, 255]
            return literal(
                red: components[value / 36],
                green: components[(value / 6) % 6],
                blue: components[value % 6]
            )
        }
        let gray = 8 + (index - 232) * 10
        return literal(red: gray, green: gray, blue: gray)
    }

    private func literal(red: Int, green: Int, blue: Int) -> Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

/// Native result-side read card for a Host-admitted `card:'read'` envelope.
/// The Core adapter owns every payload validation; this view only renders the
/// typed projection and never interprets tool arguments as source content.
private struct NativeReadToolCardBody: View {
    let presentation: NativeReadCardPresentation
    let maxLines: Int

    @State private var expanded = false
    @State private var copied = false

    private var window: NativeReadCardWindowPresentation {
        NativeReadCardWindowPresentation.resolve(lines: presentation.lines, maxLines: maxLines, expanded: expanded)
    }

    private var isWindowed: Bool { presentation.lines.count < presentation.totalLines }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
            HStack(spacing: OfficialUISpec.Spacing.p12) {
                Text(presentation.label)
                    .font(OfficialUISpec.Typography.codeSmall12)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if isWindowed {
                    Text(readWindowLabel)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                if let lang = presentation.lang, !lang.isEmpty {
                    Text(lang)
                        .font(OfficialUISpec.Typography.codeSmall12)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                if !presentation.lines.isEmpty {
                    Button(action: copySource) {
                        Text(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
                            .font(OfficialUISpec.Typography.xs13)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .accessibilityLabel(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
                }
            }
            .padding(.horizontal, OfficialUISpec.Spacing.p14)
            .padding(.vertical, OfficialUISpec.Spacing.p9)
            .background(OfficialUISpec.Token.markdownCodeBlockBanner)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                    lineRows(window.head)
                    if window.hiddenCount > 0 {
                        Button(action: { expanded.toggle() }) {
                            Text(expanded ? OfficialUISpec.Text.readCollapse : readExpandLabel)
                                .font(OfficialUISpec.Typography.codeBlock13)
                                .foregroundStyle(OfficialUISpec.Token.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(expanded ? OfficialUISpec.Text.readCollapseAccessibility : readExpandAccessibilityLabel)
                        .accessibilityValue(expanded ? "true" : "false")
                    }
                    lineRows(window.tail)
                }
                .padding(.vertical, OfficialUISpec.Spacing.p12)
            }
        }
        .background(OfficialUISpec.Token.markdownCodeBlock, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
    }

    @ViewBuilder
    private func lineRows(_ lines: [NativeToolReadLine]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p0) {
                Text(String(line.number))
                    .font(OfficialUISpec.Typography.codeBlock13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .frame(width: OfficialUISpec.Geometry.px48, alignment: .trailing)
                    .padding(.trailing, OfficialUISpec.Spacing.p14)
                    .accessibilityHidden(true)
                Text(line.text)
                    .font(OfficialUISpec.Typography.codeBlock13)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
            }
            .frame(minHeight: OfficialUISpec.Geometry.px22, alignment: .leading)
        }
    }

    private var readWindowLabel: String {
        OfficialUISpec.Text.readWindowTemplate
            .replacingOccurrences(of: "{shown}", with: String(presentation.lines.count))
            .replacingOccurrences(of: "{total}", with: String(presentation.totalLines))
    }

    private var readExpandLabel: String {
        OfficialUISpec.Text.readExpandTemplate.replacingOccurrences(of: "{n}", with: String(window.hiddenCount))
    }

    private var readExpandAccessibilityLabel: String {
        OfficialUISpec.Text.readExpandAccessibilityTemplate.replacingOccurrences(of: "{n}", with: String(window.hiddenCount))
    }

    private func copySource() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(presentation.lines.map(\.text).joined(separator: "\\n"), forType: .string) else { return }
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
    }
}

/// Native DiffBlock counterpart for an admitted `card:'diff'` intent. The Core
/// projection owns call/result authority and hunk validation; this view only
/// supplies the primitive's visual state, copy feedback and height cap.
private struct NativeDiffToolCardBody: View {
    let presentation: NativeDiffCardPresentation
    let maxLines: Int

    @State private var expanded = false
    @State private var copied = false

    private var rows: NativeDiffRowsPresentation {
        NativeDiffRowsPresentation.resolve(diffs: presentation.diffs)
    }

    private var window: NativeDiffWindowPresentation {
        NativeDiffWindowPresentation.resolve(rows: rows.rows, maxLines: maxLines, expanded: expanded)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                        diffRows(window.head)
                        if window.hiddenCount > 0 {
                            Button(action: { expanded.toggle() }) {
                                Text(expanded ? OfficialUISpec.Text.readCollapse : readExpandLabel)
                                    .font(OfficialUISpec.Typography.codeBlock13)
                                    .foregroundStyle(OfficialUISpec.Token.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(expanded ? OfficialUISpec.Text.diffCollapseAccessibility : diffExpandAccessibilityLabel)
                            .accessibilityValue(expanded ? "true" : "false")
                        }
                        diffRows(window.tail)
                    }
                    .padding(.horizontal, OfficialUISpec.Spacing.p14)
                    .padding(.vertical, OfficialUISpec.Spacing.p12)
                }
                Text(footer)
                    .font(OfficialUISpec.Typography.codeBlock13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .padding(.horizontal, OfficialUISpec.Spacing.p14)
                    .padding(.bottom, OfficialUISpec.Spacing.p12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: copyDiff) {
                Text(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
                    .font(OfficialUISpec.Typography.xs13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(OfficialUISpec.Token.secondary)
            .padding(.top, OfficialUISpec.Spacing.p8)
            .padding(.trailing, OfficialUISpec.Spacing.p12)
            .accessibilityLabel(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
        }
        .background(OfficialUISpec.Token.markdownCodeBlock, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
    }

    @ViewBuilder
    private func diffRows(_ source: [NativeDiffRowsPresentation.Row]) -> some View {
        ForEach(Array(source.enumerated()), id: \.offset) { _, row in
            HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p0) {
                switch row.kind {
                case .path:
                    Text(row.text)
                        .font(OfficialUISpec.Typography.codeBlock13.weight(.semibold))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .padding(.trailing, OfficialUISpec.Geometry.px56)
                case .gap:
                    Text(row.text)
                        .font(OfficialUISpec.Typography.codeBlock13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                case .deletion:
                    Text("- ")
                        .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    Text(row.text)
                        .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                case .addition:
                    Text("+ ")
                        .foregroundStyle(OfficialUISpec.Token.success)
                    Text(row.text)
                        .foregroundStyle(OfficialUISpec.Token.success)
                }
            }
            .font(OfficialUISpec.Typography.codeBlock13)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: OfficialUISpec.Geometry.px22, alignment: .leading)
        }
    }

    private var readExpandLabel: String {
        OfficialUISpec.Text.readExpandTemplate.replacingOccurrences(of: "{n}", with: String(window.hiddenCount))
    }

    private var diffExpandAccessibilityLabel: String {
        OfficialUISpec.Text.diffExpandAccessibilityTemplate.replacingOccurrences(of: "{n}", with: String(window.hiddenCount))
    }

    private var footer: String {
        OfficialUISpec.Text.diffFooterTemplate
            .replacingOccurrences(of: "{added}", with: String(rows.added))
            .replacingOccurrences(of: "{removed}", with: String(rows.removed))
            .replacingOccurrences(of: "{files}", with: String(rows.files))
            .replacingOccurrences(of: "{suffix}", with: rows.files == 1 ? "" : "s")
    }

    private func copyDiff() {
        let source = rows.rows.map { row in
            switch row.kind {
            case .deletion: "- \(row.text)"
            case .addition: "+ \(row.text)"
            case .path, .gap: row.text
            }
        }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(source, forType: .string) else { return }
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
    }
}

/// Native SearchBlock counterpart for an admitted result-side `card:'search'`.
/// Core validates its shape and provides text-only truncation recovery; this view
/// owns only capped/collapsed/copy interaction state.
private struct NativeSearchToolCardBody: View {
    let presentation: NativeSearchCardPresentation
    let maxLines: Int

    @State private var expanded = false
    @State private var collapsedFileIndices: Set<Int> = []
    @State private var copied = false

    private var rows: [NativeSearchRow] {
        NativeSearchRowsPresentation.resolve(shape: presentation.shape, collapsedFileIndices: collapsedFileIndices).rows
    }

    private var window: NativeSearchWindowPresentation {
        NativeSearchWindowPresentation.resolve(rows: rows, maxLines: maxLines, expanded: expanded)
    }

    private var isEmpty: Bool { rows.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p6) {
            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                HStack(spacing: OfficialUISpec.Spacing.p12) {
                    Text(summary)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !isEmpty {
                        Button(action: copySearch) {
                            Text(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
                                .font(OfficialUISpec.Typography.xs13)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .accessibilityLabel(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
                    }
                }
                .padding(.horizontal, OfficialUISpec.Spacing.p14)
                .padding(.vertical, OfficialUISpec.Spacing.p9)
                .background(OfficialUISpec.Token.markdownCodeBlockBanner)

                if isEmpty {
                    Text(OfficialUISpec.Text.searchEmpty)
                        .font(OfficialUISpec.Typography.codeBlock13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                        .padding(.horizontal, OfficialUISpec.Spacing.p14)
                        .padding(.vertical, OfficialUISpec.Spacing.p12)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                            searchRows(window.head)
                            if window.hiddenCount > 0 {
                                Button(action: { expanded.toggle() }) {
                                    Text(expanded ? OfficialUISpec.Text.readCollapse : readExpandLabel)
                                        .font(OfficialUISpec.Typography.codeBlock13)
                                        .foregroundStyle(OfficialUISpec.Token.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, OfficialUISpec.Spacing.p14)
                                .accessibilityLabel(expanded ? OfficialUISpec.Text.searchCollapseAccessibility : searchExpandAccessibilityLabel)
                                .accessibilityValue(expanded ? "true" : "false")
                            }
                            if let header = window.tailHeader { searchRow(header) }
                            searchRows(window.tail)
                        }
                        .padding(.top, OfficialUISpec.Spacing.p8)
                        .padding(.bottom, OfficialUISpec.Spacing.p12)
                    }
                }
            }
            .background(OfficialUISpec.Token.markdownCodeBlock, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))

            if let recovery = presentation.recovery, !recovery.isEmpty {
                Text(recovery)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func searchRows(_ source: [NativeSearchRow]) -> some View {
        ForEach(Array(source.enumerated()), id: \.offset) { _, row in
            searchRow(row)
        }
    }

    @ViewBuilder
    private func searchRow(_ row: NativeSearchRow) -> some View {
        switch row.kind {
        case .path:
            Text(row.text)
                .font(OfficialUISpec.Typography.codeBlock13)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, OfficialUISpec.Spacing.p14)
                .frame(minHeight: OfficialUISpec.Geometry.px22, alignment: .leading)
        case .match:
            HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p0) {
                Text("\(number(row.lineNumber ?? 0)): ")
                    .foregroundStyle(OfficialUISpec.Token.caption)
                Text(row.text)
                    .foregroundStyle(OfficialUISpec.Token.primary)
            }
            .font(OfficialUISpec.Typography.codeBlock13)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, OfficialUISpec.Spacing.p14)
            .frame(minHeight: OfficialUISpec.Geometry.px22, alignment: .leading)
        case .file:
            Button(action: { toggleFile(row.fileIndex) }) {
                HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p8) {
                    Text(row.text)
                        .font(OfficialUISpec.Typography.codeBlock13.weight(.semibold))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    Text(String(row.matchCount ?? 0))
                        .font(OfficialUISpec.Typography.codeBlock13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, minHeight: OfficialUISpec.Geometry.px22, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, OfficialUISpec.Spacing.p14)
            .accessibilityValue(row.collapsed ? "false" : "true")
        }
    }

    private var summary: String {
        let count = presentation.truncated
            ? OfficialUISpec.Text.searchTruncatedCountTemplate
                .replacingOccurrences(of: "{shown}", with: String(presentation.shownCount))
                .replacingOccurrences(of: "{total}", with: number(presentation.total))
            : String(presentation.shownCount)
        switch presentation.shape {
        case .paths:
            return OfficialUISpec.Text.searchPathsSummaryTemplate.replacingOccurrences(of: "{count}", with: count)
        case .matches:
            return OfficialUISpec.Text.searchMatchesSummaryTemplate
                .replacingOccurrences(of: "{count}", with: count)
                .replacingOccurrences(of: "{files}", with: String(presentation.fileCount))
        }
    }

    private var readExpandLabel: String {
        OfficialUISpec.Text.readExpandTemplate.replacingOccurrences(of: "{n}", with: String(window.hiddenCount))
    }

    private var searchExpandAccessibilityLabel: String {
        OfficialUISpec.Text.searchExpandAccessibilityTemplate.replacingOccurrences(of: "{n}", with: String(window.hiddenCount))
    }

    private func number(_ value: Double) -> String {
        value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
    }

    private func toggleFile(_ index: Int?) {
        guard let index else { return }
        if collapsedFileIndices.contains(index) {
            collapsedFileIndices.remove(index)
        } else {
            collapsedFileIndices.insert(index)
        }
    }

    private func copySearch() {
        let source: String
        switch presentation.shape {
        case let .paths(paths):
            source = paths.joined(separator: "\n")
        case let .matches(files):
            source = files.map { file in
                ([file.path] + file.matches.map { "\(number($0.lineNumber)): \($0.line)" }).joined(separator: "\n")
            }.joined(separator: "\n\n")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(source, forType: .string) else { return }
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
    }
}

/// Native WebBlock counterpart. Links are constructed only from the Foundation
/// `NativeSafeWebLink` decision and answers reuse the existing native Markdown
/// security boundary; this card never hosts HTML or WebView content.
private struct NativeWebToolCardBody: View {
    let presentation: NativeWebCardPresentation

    var body: some View {
        Group {
            switch presentation.kind {
            case let .search(answer, sources, truncated):
                searchBody(answer: answer, sources: sources, truncated: truncated)
            case let .fetch(url, statusCode, truncated):
                fetchBody(url: url, statusCode: statusCode, truncated: truncated)
            }
        }
        .padding(.vertical, OfficialUISpec.Spacing.p12)
        .padding(.horizontal, OfficialUISpec.Spacing.p14)
        .background(OfficialUISpec.Token.markdownCodeBlock, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r12, style: .continuous))
    }

    @ViewBuilder
    private func searchBody(answer: String?, sources: [NativeToolWebSource], truncated: Bool) -> some View {
        let empty = (answer == nil || answer?.isEmpty == true) && sources.isEmpty
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            if let answer, !answer.isEmpty {
                NativeMarkdownText(markdown: answer, streaming: false)
            }
            if empty {
                Text(OfficialUISpec.Text.webEmpty)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
            } else if !sources.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p10) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            sourceRow(source, ordinal: index + 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: OfficialUISpec.Geometry.px320)
            }
            if truncated {
                Text(OfficialUISpec.Text.webSourcesTruncated)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: NativeToolWebSource, ordinal: Int) -> some View {
        let link = NativeSafeWebLink.resolve(url: source.url, title: source.title)
        HStack(alignment: .top, spacing: OfficialUISpec.Spacing.p8) {
            Text("\(ordinal).")
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                nativeWebLink(link, font: OfficialUISpec.Typography.s14)
                if let snippet = source.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .textSelection(.enabled)
                }
                if let publishedAt = source.publishedAt, !publishedAt.isEmpty {
                    Text(publishedAt)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func fetchBody(url: String, statusCode: Double, truncated: Bool) -> some View {
        let link = NativeSafeWebLink.resolve(url: url, title: url)
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p6) {
            nativeWebLink(link, font: OfficialUISpec.Typography.codeBlock13)
            HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p12) {
                Text(OfficialUISpec.Text.webHTTPTemplate.replacingOccurrences(of: "{status}", with: number(statusCode)))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                if truncated {
                    Text(OfficialUISpec.Text.webContentTruncated)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func nativeWebLink(_ link: NativeSafeWebLink, font: Font) -> some View {
        if let destination = link.destination {
            Link(link.label, destination: destination)
                .font(font)
                .foregroundStyle(OfficialUISpec.Token.businessBlue)
                .textSelection(.enabled)
        } else {
            Text(link.label)
                .font(font)
                .foregroundStyle(OfficialUISpec.Token.businessBlue)
                .textSelection(.enabled)
        }
    }

    private func number(_ value: Double) -> String {
        value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
    }
}

/// Native generic details fallback. It is intentionally text/JSON only until a
/// separately approved native adapter can claim a specific Host `view.card`.
struct NativeToolDetailsBody: View {
    let invocation: NativeSessionStore.ToolInvocation?
    /// The selection is retained by the surrounding details column. A non-nil
    /// selection whose material is absent is the official out-of-window state,
    /// not the no-selection guidance state.
    let selectedCallID: String?

    var body: some View {
        Group {
            if let invocation {
                ScrollView {
                    VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p12) {
                        sectionLabel("details.input")
                        Text(invocation.arguments)
                            .font(OfficialUISpec.Typography.codeSmall12)
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        sectionLabel("details.output")
                        if let terminal = NativeRawToolCardProjector.terminal(invocation) {
                            NativeTerminalToolCardBody(presentation: terminal, maxLines: 16)
                                .id(invocation.id)
                        } else if let read = NativeRawToolCardProjector.read(invocation) {
                            NativeReadToolCardBody(presentation: read, maxLines: 16)
                                .id(invocation.id)
                        } else if let diff = NativeRawToolCardProjector.diff(invocation) {
                            NativeDiffToolCardBody(presentation: diff, maxLines: 16)
                                .id(invocation.id)
                        } else if let search = NativeRawToolCardProjector.search(invocation) {
                            NativeSearchToolCardBody(presentation: search, maxLines: 16)
                                .id(invocation.id)
                        } else if let web = NativeRawToolCardProjector.web(invocation) {
                            NativeWebToolCardBody(presentation: web)
                                .id(invocation.id)
                        } else if invocation.state == .running {
                            Text(OfficialUISpec.Text.toolDetailsRunning)
                                .font(OfficialUISpec.Typography.xs13)
                                .foregroundStyle(OfficialUISpec.Token.secondary)
                        } else {
                            Text(invocation.output ?? "")
                                .font(OfficialUISpec.Typography.codeSmall12)
                                .foregroundStyle(invocation.state == .failed ? OfficialUISpec.Token.errorPrimary : OfficialUISpec.Token.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(OfficialUISpec.Spacing.p16)
                }
            } else {
                Text(selectedCallID == nil ? OfficialUISpec.Text.detailsEmpty : locale("details.notInWindow"))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ key: String) -> some View {
        Text(locale(key))
            .font(OfficialUISpec.Typography.xsStrong13)
            .foregroundStyle(OfficialUISpec.Token.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func locale(_ key: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "ui-conversation", key: key, language: "en") ?? ""
    }
}
