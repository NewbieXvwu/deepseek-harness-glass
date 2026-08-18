import SwiftUI

/// Native generic fallback for the official `tool.call.toolview` seat.
///
/// Sources: `ui-tool/tool/components/ToolRow.tsx` and
/// `ui-tool/tool/models/tool-call-model.ts`. Plugin-specific card interiors
/// intentionally remain outside this fallback until a NativeUIManifest adapter
/// provides a separately reviewed native implementation.
struct NativeToolRow: View {
    let invocation: NativeSessionStore.ToolInvocation
    let selected: Bool
    let inspect: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
                inspect()
            } label: {
                HStack(spacing: 8) {
                    leading
                        .frame(width: 16, height: 16)
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    Text(OfficialUISpec.Text.toolSummarySeparator)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    Text(summary)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(state == .failed ? Color.red : OfficialUISpec.Token.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(stateDescription)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(invocation.arguments)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let output = invocation.output {
                        Divider()
                        Text(output)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(state == .failed ? Color.red : OfficialUISpec.Token.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? OfficialUISpec.Token.interactiveHover : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { inspect() }
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
        let firstLine = invocation.arguments.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return variant == .others && !invocation.name.isEmpty
            ? "\(invocation.name) \(OfficialUISpec.Text.toolSummarySeparator) \(firstLine)"
            : firstLine
    }

    private var state: NativeSessionStore.ToolInvocation.State { invocation.state }

    private var stateDescription: String {
        switch state {
        case .running: OfficialUISpec.Text.toolRunning
        case .completed: ""
        case .failed: OfficialUISpec.Text.toolFailed
        case .stopped: OfficialUISpec.Text.toolStopped
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch state {
        case .running:
            ProgressView().controlSize(.mini)
        case .failed:
            Circle().fill(Color.red).frame(width: 8, height: 8)
        case .stopped:
            Circle().fill(Color.orange).frame(width: 8, height: 8)
        case .completed:
            OfficialAssetImage(name: iconName, template: true)
                .frame(width: 14, height: 14)
                .foregroundStyle(OfficialUISpec.Token.secondary)
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

/// Native generic details fallback. It is intentionally text/JSON only until a
/// separately approved native adapter can claim a specific Host `view.card`.
struct NativeToolDetailsBody: View {
    let invocation: NativeSessionStore.ToolInvocation?

    var body: some View {
        Group {
            guard let invocation else {
                Text(OfficialUISpec.Text.detailsEmpty)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                return
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(invocation.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    if invocation.state == .running {
                        Text(OfficialUISpec.Text.toolDetailsRunning)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                    }
                    Text(invocation.output ?? invocation.arguments)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(invocation.state == .failed ? Color.red : OfficialUISpec.Token.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(16)
            }
        }
    }
}
