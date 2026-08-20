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

    static func attributedInlineMarkdown(_ source: String) -> AttributedString {
        let safe = sanitizedInlineMarkdown(source)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        var attributed = (try? AttributedString(markdown: safe, options: options)) ?? AttributedString(safe)
        for run in attributed.runs {
            guard let url = run.link, externalURL(from: url.absoluteString) == nil else { continue }
            attributed[run.range].link = nil
        }
        return attributed
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
            prose.append("```\(language ?? "")")
            prose.append(contentsOf: code)
            language = nil
        }
        appendProse()
        return blocks
    }
}

/// A minimal native syntax colorizer for the locked RC8 fence languages. It
/// intentionally accepts source text only: unknown grammars retain CodeBlock's
/// plain fallback and no generated HTML or executable grammar package is loaded.
enum NativeCodeHighlighter {
    enum Kind: Equatable { case plain, keyword, string, number, comment }
    struct Fragment: Equatable {
        let text: String
        let kind: Kind
    }

    private static let supportedLanguages: Set<String> = [
        "swift", "json", "bash", "sh", "shell", "typescript", "ts", "javascript", "js", "python", "py",
    ]
    private static let keywords: Set<String> = [
        "let", "var", "func", "struct", "class", "enum", "protocol", "extension", "import", "return", "if", "else", "for", "while", "switch", "case", "break", "continue", "throw", "throws", "async", "await", "true", "false", "null", "nil", "def", "in", "from", "const", "export", "default",
    ]

    static func fragments(code: String, language: String?) -> [Fragment] {
        guard let language, supportedLanguages.contains(language.lowercased()) else {
            return [.init(text: code, kind: .plain)]
        }
        var fragments: [Fragment] = []
        var index = code.startIndex

        func append(_ text: String, _ kind: Kind) {
            guard !text.isEmpty else { return }
            if fragments.last?.kind == kind {
                let previous = fragments.removeLast()
                fragments.append(.init(text: previous.text + text, kind: kind))
            } else {
                fragments.append(.init(text: text, kind: kind))
            }
        }

        while index < code.endIndex {
            if code[index...].hasPrefix("//") || code[index...].hasPrefix("#") {
                let end = code[index...].firstIndex(of: "\n") ?? code.endIndex
                append(String(code[index..<end]), .comment)
                index = end
            } else if code[index] == "\"" || code[index] == "'" {
                let quote = code[index]
                var end = code.index(after: index)
                var escaped = false
                while end < code.endIndex {
                    let character = code[end]
                    if character == quote && !escaped {
                        end = code.index(after: end)
                        break
                    }
                    escaped = character == "\\" && !escaped
                    if character != "\\" { escaped = false }
                    end = code.index(after: end)
                }
                append(String(code[index..<end]), .string)
                index = end
            } else if code[index].isNumber {
                var end = index
                while end < code.endIndex, code[end].isNumber || code[end] == "." { end = code.index(after: end) }
                append(String(code[index..<end]), .number)
                index = end
            } else if code[index].isLetter || code[index] == "_" {
                var end = index
                while end < code.endIndex, code[end].isLetter || code[end].isNumber || code[end] == "_" { end = code.index(after: end) }
                let word = String(code[index..<end])
                append(word, keywords.contains(word) ? .keyword : .plain)
                index = end
            } else {
                append(String(code[index]), .plain)
                index = code.index(after: index)
            }
        }
        return fragments
    }

    static func text(code: String, language: String?) -> Text {
        fragments(code: code, language: language).reduce(Text(verbatim: "")) { result, fragment in
            let color: Color
            switch fragment.kind {
            case .plain: color = OfficialUISpec.Token.primary
            case .keyword: color = OfficialUISpec.Token.businessBlue
            case .string: color = OfficialUISpec.Token.success
            case .number: color = OfficialUISpec.Token.caption
            case .comment: color = OfficialUISpec.Token.secondary
            }
            return result + Text(verbatim: fragment.text).foregroundColor(color)
        }
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
        NativeMarkdownSecurityPolicy.attributedInlineMarkdown(text)
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
                NativeCodeHighlighter.text(code: displayedCode, language: language)
                    .font(OfficialUISpec.Typography.codeSmallStrong12)
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
