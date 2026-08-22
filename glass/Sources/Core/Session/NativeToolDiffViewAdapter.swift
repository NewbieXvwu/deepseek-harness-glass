import Foundation

/// Core owns strict raw-JSON admission for the official diff card. The adapter
/// deliberately rejects a missing `oldText`: rc.2's narrowDiffs treats only a
/// JSON null or string as valid, never an omitted field.
extension ToolEventViewDTO {
    var nativeDiffView: NativeToolDiffView? {
        guard let object = view.objectValue,
              let card = object["card"]?.stringValue,
              card == "diff",
              let values = object["diffs"]?.arrayValue,
              !values.isEmpty
        else { return nil }

        var diffs: [NativeToolDiffHunk] = []
        diffs.reserveCapacity(values.count)
        for value in values {
            guard let hunk = value.objectValue,
                  let path = hunk["path"]?.stringValue,
                  let newText = hunk["newText"]?.stringValue,
                  let oldValue = hunk["oldText"]
            else { return nil }
            let oldText: String?
            switch oldValue {
            case .null:
                oldText = nil
            case let .string(text):
                oldText = text
            default:
                return nil
            }
            diffs.append(.init(path: path, oldText: oldText, newText: newText))
        }
        return .init(card: card, diffs: diffs)
    }
}
