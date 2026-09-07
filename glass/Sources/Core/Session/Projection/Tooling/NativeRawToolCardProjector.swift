import Foundation

/// rc.1 card derivation from durable Tool call/result facts. This deliberately
/// consumes arguments, inner tool-result content and result metadata instead of
/// the removed rc.2 `ToolEventView` presenter carrier.
enum NativeRawToolCardProjector {
    static func terminal(_ invocation: NativeSessionStore.ToolInvocation) -> NativeTerminalCardPresentation? {
        guard invocation.parentCallID == nil, let args = arguments(invocation.arguments) else { return nil }
        let shell = shellCall(name: invocation.name, args: args)
        let send = terminalSendCall(name: invocation.name, args: args)
        guard let call = shell.map(TerminalCall.shell) ?? send.map(TerminalCall.send), !call.background else { return nil }

        let cwd = resolvedTerminalCWD(workdir: call.workdir, sessionCWD: invocation.sessionCWD)
        if invocation.state == .running {
            return .init(
                command: call.command,
                description: call.description,
                cwd: cwd,
                output: nil,
                exitCode: nil,
                signal: nil,
                running: true
            )
        }
        guard invocation.resultIsError != true, !call.persistent,
              let text = singleResultText(invocation.resultContent)
        else { return nil }
        let status = call.isTerminalSend ? TerminalStatus(output: text, exitCode: nil, signal: nil) : parseExitStatus(text)
        return .init(
            command: call.command,
            description: call.description,
            cwd: cwd,
            output: status.output,
            exitCode: status.exitCode,
            signal: status.signal,
            running: false
        )
    }

    static func read(_ invocation: NativeSessionStore.ToolInvocation) -> NativeReadCardPresentation? {
        guard invocation.parentCallID == nil,
              invocation.state != .running,
              invocation.resultIsError == false,
              validReadCall(name: invocation.name, raw: invocation.arguments),
              let meta = readMeta(invocation.resultMeta),
              let text = singleResultText(invocation.resultContent),
              matchesReadEnvelope(text)
        else { return nil }
        return .init(
            label: relativeLabel(meta.path, cwd: invocation.sessionCWD),
            lines: meta.lines,
            totalLines: meta.totalLines,
            lang: meta.lang
        )
    }

    static func diff(_ invocation: NativeSessionStore.ToolInvocation) -> NativeDiffCardPresentation? {
        guard invocation.parentCallID == nil,
              let args = arguments(invocation.arguments),
              let intended = intendedDiff(name: invocation.name, args: args)
        else { return nil }
        if invocation.state == .running {
            return .init(diffs: [intended.diff], source: .call)
        }
        guard invocation.resultIsError == false, intended.tool != .strReplaceEditor else { return nil }
        switch appliedDiffs(invocation.resultMeta) {
        case let .diffs(diffs): return .init(diffs: diffs, source: .result)
        case .empty, .invalid:
            return intended.tool == .write ? .init(diffs: [intended.diff], source: .result) : nil
        }
    }

    static func search(_ invocation: NativeSessionStore.ToolInvocation) -> NativeSearchCardPresentation? {
        guard invocation.parentCallID == nil,
              invocation.state != .running,
              invocation.resultIsError == false,
              let tool = validSearchCall(name: invocation.name, raw: invocation.arguments),
              let meta = invocation.resultMeta?.objectValue,
              let truncated = meta["truncated"]?.boolValue,
              let total = nonNegativeInteger(meta["total"])
        else { return nil }
        let recovery = truncated ? textResult(invocation.resultContent) : nil
        switch tool {
        case .grep:
            guard meta["shape"]?.stringValue == "matches",
                  let values = meta["files"]?.arrayValue,
                  let files = searchFiles(values)
            else { return nil }
            return .init(title: nil, truncated: truncated, total: Double(total), shape: .matches(files), recovery: recovery)
        case .glob:
            guard meta["shape"]?.stringValue == "paths", let values = meta["paths"]?.arrayValue else { return nil }
            var paths: [String] = []
            paths.reserveCapacity(values.count)
            for value in values {
                guard let path = value.stringValue else { return nil }
                paths.append(path)
            }
            return .init(title: nil, truncated: truncated, total: Double(total), shape: .paths(paths), recovery: recovery)
        }
    }

    static func web(_ invocation: NativeSessionStore.ToolInvocation) -> NativeWebCardPresentation? {
        guard invocation.parentCallID == nil,
              invocation.state != .running,
              invocation.resultIsError == false,
              let tool = validWebCall(name: invocation.name, raw: invocation.arguments),
              let meta = invocation.resultMeta?.objectValue,
              let truncated = meta["truncated"]?.boolValue
        else { return nil }
        switch tool {
        case .search:
            guard let values = meta["sources"]?.arrayValue, let sources = webSources(values) else { return nil }
            let answer: String?
            if let value = meta["answer"] {
                guard let string = value.stringValue else { return nil }
                answer = string
            } else {
                answer = nil
            }
            return .init(kind: .search(answer: answer, sources: sources, truncated: truncated))
        case .fetch:
            guard let url = meta["url"]?.stringValue, let status = integer(meta["statusCode"]) else { return nil }
            return .init(kind: .fetch(url: url, statusCode: Double(status), truncated: truncated))
        }
    }

    // MARK: - Raw rc.1 narrowing

    private static func arguments(_ raw: String) -> [String: JSONValue]? {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return value.objectValue
    }

    private static func validEscalationFields(_ args: [String: JSONValue]) -> Bool {
        let permission = args["sandbox_permissions"]?.stringValue
        let justification = args["justification"]?.stringValue
        if args["sandbox_permissions"] == nil && args["justification"] == nil { return true }
        guard permission == "workspace-write" || permission == "danger-full-access" else { return false }
        return justification?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private struct ShellCall {
        let command: String
        let description: String?
        let workdir: String?
        let persistent: Bool
        let background: Bool
    }

    private struct SendCall {
        let text: String
        let sessionID: String
        let background: Bool
    }

    private enum TerminalCall {
        case shell(ShellCall)
        case send(SendCall)

        var command: String {
            switch self {
            case let .shell(call): call.command
            case let .send(call): call.text.isEmpty ? "(send input)" : call.text
            }
        }
        var description: String? {
            switch self {
            case let .shell(call): call.description
            case let .send(call): "Terminal \(call.sessionID)"
            }
        }
        var workdir: String? { if case let .shell(call) = self { call.workdir } else { nil } }
        var persistent: Bool { if case let .shell(call) = self { call.persistent } else { false } }
        var background: Bool {
            switch self { case let .shell(call): call.background; case let .send(call): call.background }
        }
        var isTerminalSend: Bool { if case .send = self { true } else { false } }
    }

    private static func shellCall(name: String, args: [String: JSONValue]) -> ShellCall? {
        guard name == "bash" || name == "pwsh",
              let command = args["command"]?.stringValue,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validEscalationFields(args)
        else { return nil }
        if let timeout = args["timeoutMs"]?.numberValue, (!timeout.isFinite || timeout <= 0) { return nil }
        if args["timeoutMs"] != nil && args["timeoutMs"]?.numberValue == nil { return nil }
        if args["workdir"] != nil && args["workdir"]?.stringValue == nil { return nil }
        if args["run_in_background"] != nil && args["run_in_background"]?.boolValue == nil { return nil }
        if args["description"] == nil {
            return .init(command: command, description: nil, workdir: nil, persistent: true, background: false)
        }
        guard let description = args["description"]?.stringValue,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return .init(
            command: command,
            description: description,
            workdir: args["workdir"]?.stringValue,
            persistent: false,
            background: args["run_in_background"]?.boolValue == true
        )
    }

    private static func terminalSendCall(name: String, args: [String: JSONValue]) -> SendCall? {
        guard name == "terminal_send",
              let sessionID = args["sessionId"]?.stringValue, !sessionID.isEmpty,
              let text = args["text"]?.stringValue
        else { return nil }
        if args["submit"] != nil && args["submit"]?.boolValue == nil { return nil }
        if args["run_in_background"] != nil && args["run_in_background"]?.boolValue == nil { return nil }
        return .init(text: text, sessionID: sessionID, background: args["run_in_background"]?.boolValue == true)
    }

    private struct TerminalStatus { let output: String; let exitCode: Int?; let signal: String? }

    private static func parseExitStatus(_ text: String) -> TerminalStatus {
        if text.hasSuffix("]") {
            if let lastNewline = text.lastIndex(of: "\n") {
                let tail = text[text.index(after: lastNewline)...]
                if tail.hasPrefix("[killed by signal: ") && tail.hasSuffix("]") {
                    let sig = tail.dropFirst("[killed by signal: ".count).dropLast()
                    if !sig.contains("\n") && !sig.contains("]") {
                        return .init(output: String(text[..<lastNewline]), exitCode: nil, signal: String(sig))
                    }
                }
                if tail.hasPrefix("[exit code: ") && tail.hasSuffix("]") {
                    let digits = tail.dropFirst("[exit code: ".count).dropLast()
                    if let code = Int(digits) {
                        return .init(output: String(text[..<lastNewline]), exitCode: code, signal: nil)
                    }
                }
            }
        }
        return .init(output: text, exitCode: 0, signal: nil)
    }

    private static func resolvedTerminalCWD(workdir: String?, sessionCWD: String?) -> String? {
        guard let workdir, !workdir.isEmpty else { return sessionCWD }
        let joined = NativeProjectPathResolver.resolve(cwd: sessionCWD, path: workdir)
        return normalizedSegments(joined)
    }

    private static func normalizedSegments(_ path: String) -> String {
        guard path.contains("/.") || path.contains("\\.") || path.hasPrefix(".") else { return path }
        let separator: Character = path.contains("\\") && !path.contains("/") ? "\\" : "/"
        let rooted = path.first == "/" || path.first == "\\"
        var kept: [Substring] = []
        for part in path.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
            if part == "." { continue }
            if part == ".." {
                if !kept.isEmpty && kept.last != ".." { kept.removeLast() }
                else if !rooted { kept.append(part) }
            } else { kept.append(part) }
        }
        let body = kept.joined(separator: String(separator))
        return rooted ? String(separator) + body : body
    }

    private struct ReadMeta {
        let path: String
        let lines: [NativeToolReadLine]
        let totalLines: Int
        let lang: String?
    }

    private static func validReadCall(name: String, raw: String) -> Bool {
        guard name == "read", let args = arguments(raw),
              let path = args["file_path"]?.stringValue,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        if let offset = args["offset"], guardPositiveInteger(offset) == nil { return false }
        if let limit = args["limit"], guardPositiveInteger(limit) == nil { return false }
        return true
    }

    private static func readMeta(_ value: JSONValue?) -> ReadMeta? {
        guard let meta = value?.objectValue,
              let path = meta["path"]?.stringValue,
              let offset = guardPositiveInteger(meta["offset"]),
              let total = nonNegativeInteger(meta["totalLines"]),
              let values = meta["lines"]?.arrayValue
        else { return nil }
        if meta["lang"] != nil && meta["lang"]?.stringValue == nil { return nil }
        var previous = offset - 1
        var lines: [NativeToolReadLine] = []
        for value in values {
            guard let line = value.objectValue,
                  let number = guardPositiveInteger(line["number"]), number > previous, number <= total,
                  let text = line["text"]?.stringValue
            else { return nil }
            previous = number
            lines.append(.init(number: number, text: text))
        }
        return .init(path: path, lines: lines, totalLines: total, lang: meta["lang"]?.stringValue)
    }

    private static func matchesReadEnvelope(_ text: String) -> Bool {
        guard text.hasPrefix("<path>"),
              text.hasSuffix("\n</content>"),
              let separatorRange = text.range(of: "</path>\n<type>file</type>\n<content>\n")
        else { return false }
        let pathContent = text[text.index(text.startIndex, offsetBy: 6)..<separatorRange.lowerBound]
        return !pathContent.contains("\n")
    }

    private static func relativeLabel(_ path: String, cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return path }
        let root = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        let normalizedRoot = cwd.hasPrefix("/") ? "/" + root : root
        if path.hasPrefix(normalizedRoot + "/") || path.hasPrefix(normalizedRoot + "\\") {
            return String(path.dropFirst(normalizedRoot.count + 1))
        }
        return path
    }

    private enum MutationTool { case write, edit, strReplaceEditor }
    private struct IntendedDiff { let tool: MutationTool; let diff: NativeToolDiffHunk }

    private static func intendedDiff(name: String, args: [String: JSONValue]) -> IntendedDiff? {
        if name == "str_replace_editor" {
            guard let path = args["path"]?.stringValue, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let command = args["command"]?.stringValue
            else { return nil }
            if command == "create" {
                if args["file_text"] != nil && args["file_text"]?.stringValue == nil { return nil }
                return .init(tool: .strReplaceEditor, diff: .init(path: path, oldText: nil, newText: args["file_text"]?.stringValue ?? ""))
            }
            if command == "str_replace" {
                if args["old_str"] != nil && args["old_str"]?.stringValue == nil { return nil }
                if args["new_str"] != nil && args["new_str"]?.stringValue == nil { return nil }
                return .init(tool: .strReplaceEditor, diff: .init(path: path, oldText: args["old_str"]?.stringValue, newText: args["new_str"]?.stringValue ?? ""))
            }
            return nil
        }
        guard let path = args["file_path"]?.stringValue,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validEscalationFields(args)
        else { return nil }
        if name == "write", let content = args["content"]?.stringValue {
            return .init(tool: .write, diff: .init(path: path, oldText: nil, newText: content))
        }
        guard name == "edit",
              let old = args["old_string"]?.stringValue,
              let new = args["new_string"]?.stringValue
        else { return nil }
        if args["replace_all"] != nil && args["replace_all"]?.boolValue == nil { return nil }
        return .init(tool: .edit, diff: .init(path: path, oldText: old.isEmpty ? nil : old, newText: new))
    }

    private enum AppliedDiffs { case diffs([NativeToolDiffHunk]), empty, invalid }
    private static func appliedDiffs(_ value: JSONValue?) -> AppliedDiffs {
        guard let meta = value?.objectValue, let values = meta["diffs"]?.arrayValue else { return .invalid }
        if values.isEmpty { return .empty }
        var diffs: [NativeToolDiffHunk] = []
        for value in values {
            guard let hunk = value.objectValue,
                  let path = hunk["path"]?.stringValue,
                  let newText = hunk["newText"]?.stringValue,
                  let old = hunk["oldText"]
            else { return .invalid }
            let oldText: String?
            switch old {
            case .null: oldText = nil
            case let .string(text): oldText = text
            default: return .invalid
            }
            diffs.append(.init(path: path, oldText: oldText, newText: newText))
        }
        return .diffs(diffs)
    }

    private enum SearchTool { case grep, glob }
    private static func validSearchCall(name: String, raw: String) -> SearchTool? {
        guard let args = arguments(raw), let pattern = args["pattern"]?.stringValue else { return nil }
        if args["path"] != nil {
            guard let path = args["path"]?.stringValue, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        }
        if name == "grep" {
            guard !pattern.isEmpty else { return nil }
            if let include = args["include"]?.stringValue, !validInclude(include) { return nil }
            if args["include"] != nil && args["include"]?.stringValue == nil { return nil }
            return .grep
        }
        guard name == "glob", !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .glob
    }

    private static func validInclude(_ value: String) -> Bool {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.hasPrefix("!") { return false }
        var depth = 0
        for character in value {
            if character == "{" { depth += 1 }
            else if character == "}" { depth = max(0, depth - 1) }
            else if character == "," && depth == 0 { return false }
        }
        return true
    }

    private static func searchFiles(_ values: [JSONValue]) -> [NativeToolSearchFileGroup]? {
        var files: [NativeToolSearchFileGroup] = []
        for value in values {
            guard let file = value.objectValue, let path = file["path"]?.stringValue, let matches = file["matches"]?.arrayValue else { return nil }
            var narrowed: [NativeToolSearchLineMatch] = []
            for matchValue in matches {
                guard let match = matchValue.objectValue,
                      let number = guardPositiveInteger(match["lineNumber"]),
                      let line = match["line"]?.stringValue
                else { return nil }
                narrowed.append(.init(lineNumber: Double(number), line: line))
            }
            files.append(.init(path: path, matches: narrowed))
        }
        return files
    }

    private enum WebTool { case search, fetch }
    private static func validWebCall(name: String, raw: String) -> WebTool? {
        guard let args = arguments(raw) else { return nil }
        if name == "web_search" {
            guard let values = args["queries"]?.arrayValue, !values.isEmpty else { return nil }
            for value in values {
                guard let query = value.stringValue, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            }
            return .search
        }
        if name == "web_fetch", let url = args["url"]?.stringValue, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .fetch }
        return nil
    }

    private static func webSources(_ values: [JSONValue]) -> [NativeToolWebSource]? {
        var sources: [NativeToolWebSource] = []
        for value in values {
            guard let source = value.objectValue, let url = source["url"]?.stringValue else { return nil }
            for key in ["title", "snippet", "publishedAt"] where source[key] != nil && source[key]?.stringValue == nil { return nil }
            sources.append(.init(
                url: url,
                title: source["title"]?.stringValue,
                snippet: source["snippet"]?.stringValue,
                publishedAt: source["publishedAt"]?.stringValue
            ))
        }
        return sources
    }

    private static func singleResultText(_ content: [JSONValue]?) -> String? {
        guard let content, content.count == 1,
              let object = content[0].objectValue,
              object["type"]?.stringValue == "text"
        else { return nil }
        return object["text"]?.stringValue
    }

    private static func textResult(_ content: [JSONValue]?) -> String? {
        let text = (content ?? []).compactMap { value -> String? in
            guard let object = value.objectValue, object["type"]?.stringValue == "text" else { return nil }
            return object["text"]?.stringValue
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue, number.isFinite, number.rounded(.towardZero) == number,
              number >= Double(Int.min), number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
    private static func nonNegativeInteger(_ value: JSONValue?) -> Int? { integer(value).flatMap { $0 >= 0 ? $0 : nil } }
    private static func guardPositiveInteger(_ value: JSONValue?) -> Int? { integer(value).flatMap { $0 >= 1 ? $0 : nil } }
}
