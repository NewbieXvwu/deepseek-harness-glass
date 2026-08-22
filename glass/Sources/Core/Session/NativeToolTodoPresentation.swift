import Foundation

/// The one-line todo_write summary split at the official ellipsis boundary.
/// UI owns locale joining; this Core value deliberately carries only facts.
public struct NativeToolTodoSummary: Equatable, Sendable {
    public let done: Int
    public let total: Int
    public let activeContent: String?
    public let activeExtra: Int

    public init(done: Int, total: Int, activeContent: String?, activeExtra: Int) {
        self.done = done
        self.total = total
        self.activeContent = activeContent
        self.activeExtra = activeExtra
    }
}

/// Foundation-only admission for rc.2's keyed `todo_write` row. It reads only
/// the call args retained by the generic tool node: a failure to parse or an
/// invalid `todos` envelope is not a partial todo card and must fall back.
public enum NativeToolTodoPresentation {
    public static func resolve(toolName: String, arguments: String) -> NativeToolTodoSummary? {
        guard toolName == "todo_write",
              let data = arguments.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data),
              let values = root as? [String: Any],
              let todos = values["todos"] as? [Any],
              todos.allSatisfy(isPlanItem)
        else { return nil }

        let active = todos.filter { itemValue($0, key: "status") as? String == "in_progress" }
        let firstContent = active.first.flatMap { itemValue($0, key: "content") as? String }
        let activeContent = firstContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? firstContent
            : nil
        return .init(
            done: todos.filter { itemValue($0, key: "status") as? String == "completed" }.count,
            total: todos.count,
            activeContent: activeContent,
            activeExtra: activeContent == nil ? 0 : active.count - 1
        )
    }

    /// JavaScript `typeof value === 'object' && value !== null`: JSON arrays
    /// qualify and simply expose no content/status properties to the summary.
    private static func isPlanItem(_ value: Any) -> Bool {
        value is [String: Any] || value is [Any] || value is NSDictionary || value is NSArray
    }

    private static func itemValue(_ item: Any, key: String) -> Any? {
        if let dictionary = item as? [String: Any] { return dictionary[key] }
        if let dictionary = item as? NSDictionary { return dictionary[key] }
        return nil
    }
}
