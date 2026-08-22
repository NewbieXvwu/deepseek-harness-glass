import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native rc.2 `tool-call-model` summary derivation. File tools deliberately use
/// `path`/`file_path` rather than showing their raw JSON arguments in the
/// collapsed row; this is also the summary that a file-mutation tool view uses.
enum NativeToolRowModel {
    static func summary(toolName: String, arguments: String, isGeneric: Bool, separator: String) -> String {
        let base = preferredSummary(toolName: toolName, arguments: arguments) ?? firstLine(arguments)
        return isGeneric && !toolName.isEmpty ? "\(toolName) \(separator) \(base)" : base
    }

    /// Mirrors the rc.2 `tool-call-model` summary order without granting a non-file
    /// invocation an openable project path. The collapsed row can abbreviate a URL
    /// or command, but only the verified file-path seam becomes a workspace action.
    static func filePath(toolName: String, arguments: String) -> String? {
        guard isFileTool(toolName), let values = object(arguments) else { return nil }
        return firstString(in: values, keys: ["path", "file_path"])
    }

    private static func preferredSummary(toolName: String, arguments: String) -> String? {
        guard let values = object(arguments) else { return nil }
        if isSearchTool(toolName), let queries = values["queries"] as? [Any] {
            let nonempty = queries.compactMap { ($0 as? String).flatMap { $0.isEmpty ? nil : firstLine($0) } }
            if !nonempty.isEmpty { return nonempty.joined(separator: ", ") }
        }
        return firstString(in: values, keys: summaryKeys(for: toolName))
    }

    private static func object(_ arguments: String) -> [String: Any]? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object as? [String: Any]
    }

    private static func firstString(in values: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key] as? String, !value.isEmpty {
                return firstLine(value)
            }
        }
        return nil
    }

    private static func summaryKeys(for toolName: String) -> [String] {
        switch toolName {
        case "bash", "pwsh": ["description", "command"]
        case "read", "web_fetch", "cordis_package_inspect", "cordis_runtime_inspect": ["path", "file_path", "url"]
        case "web_search", "grep", "glob": ["query", "pattern", "url"]
        case "write", "edit": ["path", "file_path"]
        case "run_code": ["description"]
        default: []
        }
    }

    private static func isSearchTool(_ toolName: String) -> Bool {
        ["web_search", "grep", "glob"].contains(toolName)
    }

    private static func isFileTool(_ toolName: String) -> Bool {
        ["read", "web_fetch", "cordis_package_inspect", "cordis_runtime_inspect", "write", "edit"].contains(toolName)
    }

    private static func firstLine(_ value: String) -> String {
        value.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    }
}

/// rc.2 `tool-call-model` expanded input projection. It deliberately keeps this
/// generic row model separate from specialized card selection: the Host has not
/// yet supplied an admitted typed `view`, so all data remains text/JSON.
enum NativeToolRowPresentation {
    static func body(toolName: String, arguments: String) -> String? {
        guard !arguments.isEmpty else { return nil }
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return arguments }

        if toolName == "run_code",
           let values = object as? [String: Any],
           let code = values["code"] as? String,
           !code.isEmpty {
            return code
        }

        guard JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let value = String(data: pretty, encoding: .utf8)
        else { return arguments }
        return value
    }
}
