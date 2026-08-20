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

    @discardableResult
    static func openExternal(_ candidate: URL, opener: (URL) -> Void) -> Bool {
        guard let permitted = externalURL(from: candidate.absoluteString) else { return false }
        opener(permitted)
        return true
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
        case quote(id: Int, text: String)
        case list(id: Int, ordered: Bool, items: [String])
        case code(id: Int, language: String?, code: String)

        var id: Int {
            switch self {
            case let .prose(id, _), let .quote(id, _), let .list(id, _, _), let .code(id, _, _): id
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
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

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

        while index < lines.count {
            let line = lines[index]
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
                index += 1
                continue
            }
            if inFence {
                code.append(line)
                index += 1
                continue
            }
            if line == ">" || line.hasPrefix("> ") {
                appendProse()
                var quote: [String] = []
                while index < lines.count, lines[index] == ">" || lines[index].hasPrefix("> ") {
                    quote.append(lines[index] == ">" ? "" : String(lines[index].dropFirst(2)))
                    index += 1
                }
                blocks.append(.quote(id: nextID, text: quote.joined(separator: "\n")))
                nextID += 1
                continue
            }
            if let firstMarker = listMarker(in: line) {
                appendProse()
                var items: [String] = []
                let ordered = firstMarker.ordered
                while index < lines.count, let marker = listMarker(in: lines[index]), marker.ordered == ordered {
                    items.append(marker.text)
                    index += 1
                }
                blocks.append(.list(id: nextID, ordered: ordered, items: items))
                nextID += 1
                continue
            }
            prose.append(line)
            index += 1
        }
        if inFence {
            // An incomplete streaming fence remains literal prose until its
            // closing delimiter arrives, matching RC8's conservative tail rule.
            prose.append("```\(language ?? "")")
            prose.append(contentsOf: code)
        }
        appendProse()
        return blocks
    }

    private static func listMarker(in line: String) -> (ordered: Bool, text: String)? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return (false, String(line.dropFirst(prefix.count)))
        }
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return (true, String(rest.dropFirst(2)))
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
        fragments(code: code, language: language).reduce(Text(String())) { result, fragment in
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
                case let .quote(_, text):
                    NativeMarkdownQuote(text: text)
                case let .list(_, ordered, items):
                    NativeMarkdownList(ordered: ordered, items: items)
                case let .code(_, language, code):
                    NativeMarkdownCodeBlock(code: code, language: language)
                }
            }
        }
        .accessibilityLabel(NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown(markdown))
        .accessibilityValue(streaming ? OfficialUISpec.Text.running : "")
        .environment(\.openURL, OpenURLAction { candidate in
            NativeMarkdownSecurityPolicy.openExternal(candidate) { permitted in
                NSWorkspace.shared.open(permitted)
            } ? .handled : .discarded
        })
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

private struct NativeMarkdownQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: OfficialUISpec.Spacing.p8) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(OfficialUISpec.Token.caption)
                .frame(width: 2)
            Text(NativeMarkdownSecurityPolicy.attributedInlineMarkdown(text))
                .font(OfficialUISpec.Typography.base16)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeMarkdownList: View {
    let ordered: Bool
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p8) {
                    Text(ordered ? "\(offset + 1)." : "•")
                        .font(OfficialUISpec.Typography.base16)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .frame(minWidth: ordered ? 22 : 12, alignment: .trailing)
                    Text(NativeMarkdownSecurityPolicy.attributedInlineMarkdown(item))
                        .font(OfficialUISpec.Typography.base16)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
