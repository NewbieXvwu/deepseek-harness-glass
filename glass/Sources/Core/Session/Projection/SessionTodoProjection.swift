import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// One item of the official Host-owned whole `todos` projection. Consumers must
/// treat the list as a replacement snapshot, never merge it with locally
/// remembered check states or tool-call output.
struct CoreTodoItem: Equatable {
    enum Status: String, Equatable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    let content: String
    let status: Status
}

/// Strict decoder for the `todos` Session projection. `nil` means capability
/// absent or Host tombstone; `[]` is a valid empty whole list. Unknown status,
/// duplicate content, or malformed item fails closed rather than fabricating a
/// partial plan in native UI.
@MainActor
enum SessionTodoProjectionReader {
    static func value(from store: SessionProjectionStore, sessionID: String) -> [CoreTodoItem]? {
        guard let value = store.value(sessionID: sessionID, key: "todos"), value != .null else { return nil }
        guard let rawItems = value.arrayValue else { return nil }
        var seen = Set<String>()
        var decoded: [CoreTodoItem] = []
        for rawItem in rawItems {
            guard let item = rawItem.objectValue,
                  let content = item["content"]?.stringValue,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let statusRaw = item["status"]?.stringValue,
                  let status = CoreTodoItem.Status(rawValue: statusRaw),
                  seen.insert(content).inserted
            else { return nil }
            decoded.append(.init(content: content, status: status))
        }
        return decoded
    }
}
