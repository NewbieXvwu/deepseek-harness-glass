import Foundation
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Security boundary for untrusted Host-authored Markdown. A destination is
/// interactive only when it is an absolute HTTP(S) URL; the renderer never
/// delegates `file:`, `data:`, `javascript:` or relative destinations to macOS.
enum NativeMarkdownSecurityPolicy {
    static func externalURL(from raw: String) -> URL? {
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              components.host?.isEmpty == false,
              let url = components.url
        else { return nil }
        return url
    }

    /// Removes executable HTML elements and turns unsafe Markdown links into
    /// inert prose before `AttributedString` receives the document. This is a
    /// defensive parser boundary, not an HTML renderer or sanitizer bypass.
    static func sanitizedInlineMarkdown(_ source: String) -> String {
        var result = source
        result = result.replacingOccurrences(
            of: #"(?is)<(script|style|iframe|object|embed)[^>]*>.*?</\1>"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)

        let pattern = #"\[([^\]]*)\]\(([^\s\)]+)(?:\s+[^\)]*)?\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return result }
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let labelRange = Range(match.range(at: 1), in: result),
                  let destinationRange = Range(match.range(at: 2), in: result),
                  let fullRange = Range(match.range(at: 0), in: result)
            else { continue }
            let label = String(result[labelRange])
            let destination = String(result[destinationRange])
            let replacement = externalURL(from: destination) == nil ? "\(label) (\(destination))" : String(result[fullRange])
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }
}

/// A deliberately bounded native document model. Fence boundaries are resolved
/// before inline Markdown parsing so code is always copied/rendered as literal
/// text and cannot accidentally become a rich-text or link execution channel.
enum NativeMarkdownDocument {
    enum Block: Identifiable, Equatable {
        case prose(id: Int, text: String)
        case code(id: Int, language: String?, code: String)

        var id: Int {
            switch self {
            case let .prose(id, _), let .code(id, _, _): id
            }
        }
    }

    static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [String] = []
        var code: [String] = []
        var language: String?
        var inFence = false
        var nextID = 0

        func appendProse() {
            guard !prose.isEmpty else { return }
            blocks.append(.prose(id: nextID, text: prose.joined(separator: "\n")))
            nextID += 1
            prose.removeAll(keepingCapacity: true)
        }

        func appendCode() {
            blocks.append(.code(id: nextID, language: language, code: code.joined(separator: "\n")))
            nextID += 1
            code.removeAll(keepingCapacity: true)
            language = nil
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("```") {
                if inFence {
                    appendCode()
                    inFence = false
                } else {
                    appendProse()
                    let hint = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    language = hint.isEmpty ? nil : hint
                    inFence = true
                }
                continue
            }
            if inFence { code.append(line) } else { prose.append(line) }
        }
        if inFence {
            // An incomplete streaming fence remains literal prose until its
            // closing delimiter arrives, matching RC8's conservative tail rule.
            prose.append("```\(language ?? \"\")")
            prose.append(contentsOf: code)
            language = nil
        }
        appendProse()
        return blocks
    }
}

/// Native counterpart to RC8 MarkdownText. It accepts only the bounded
/// document model above and gives SwiftUI a sanitized AttributedString; raw HTML
/// is never supplied to a web or HTML rendering surface.
struct NativeMarkdownText: View {
    let markdown: String
    let streaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            ForEach(NativeMarkdownDocument.parse(markdown)) { block in
                switch block {
                case let .prose(_, text):
                    NativeMarkdownProse(text: text)
                case let .code(_, language, code):
                    NativeMarkdownCodeBlock(code: code, language: language)
                }
            }
        }
        .accessibilityLabel(NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(markdown))
        .accessibilityValue(streaming ? OfficialUISpec.Text.running : "")
    }
}

private struct NativeMarkdownProse: View {
    let text: String

    var body: some View {
        Text(attributed)
            .font(OfficialUISpec.Typography.base16)
            .foregroundStyle(OfficialUISpec.Token.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        let safe = NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(text)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return (try? AttributedString(markdown: safe, options: options)) ?? AttributedString(safe)
    }
}

private struct NativeMarkdownCodeBlock: View {
    let code: String
    let language: String?
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    private var displayedCode: String {
        code.hasSuffix("\n") ? String(code.dropLast()) : code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Text(language ?? "")
                    .font(OfficialUISpec.Typography.codeSmallStrong12)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                Spacer(minLength: 0)
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: OfficialUISpec.Layout.chatMessageActionSize, height: OfficialUISpec.Layout.chatMessageActionSize)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OfficialUISpec.Token.caption)
                .accessibilityLabel(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
            }
            .padding(.horizontal, OfficialUISpec.Spacing.p10)
            .padding(.vertical, OfficialUISpec.Spacing.p6)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayedCode)
                    .font(OfficialUISpec.Typography.codeSmallStrong12)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(OfficialUISpec.Spacing.p10)
            }
        }
        .background(OfficialUISpec.Token.conversationBubble, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.chatMessageCornerRadius, style: .continuous))
        .onDisappear {
            resetTask?.cancel()
            resetTask = nil
        }
        .accessibilityLabel(displayedCode)
    }

    private func copy() {
        guard !copied else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(code, forType: .string) else { return }
        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            copied = false
            resetTask = nil
        }
    }
}
