import Foundation

/// Strict raw-JSON admission for the official result-side search card. It mirrors
/// the model's explicit shape validation before any SwiftUI code sees search
/// groups or paths.
extension ToolEventViewDTO {
    var nativeSearchView: NativeToolSearchView? {
        guard let object = view.objectValue,
              object["card"]?.stringValue == "search",
              let shape = object["shape"]?.stringValue,
              let truncated = object["truncated"]?.boolValue,
              let total = object["total"]?.numberValue,
              total.isFinite,
              total >= 0
        else { return nil }

        let typedShape: NativeToolSearchView.Shape
        switch shape {
        case "matches":
            guard let values = object["files"]?.arrayValue else { return nil }
            var files: [NativeToolSearchFileGroup] = []
            files.reserveCapacity(values.count)
            for value in values {
                guard let file = value.objectValue,
                      let path = file["path"]?.stringValue,
                      let matchValues = file["matches"]?.arrayValue
                else { return nil }
                var matches: [NativeToolSearchLineMatch] = []
                matches.reserveCapacity(matchValues.count)
                for matchValue in matchValues {
                    guard let match = matchValue.objectValue,
                          let lineNumber = match["lineNumber"]?.numberValue,
                          lineNumber.isFinite,
                          let line = match["line"]?.stringValue
                    else { return nil }
                    matches.append(.init(lineNumber: lineNumber, line: line))
                }
                files.append(.init(path: path, matches: matches))
            }
            typedShape = .matches(files)
        case "paths":
            guard let values = object["paths"]?.arrayValue else { return nil }
            var paths: [String] = []
            paths.reserveCapacity(values.count)
            for value in values {
                guard let path = value.stringValue else { return nil }
                paths.append(path)
            }
            typedShape = .paths(paths)
        default:
            return nil
        }

        return .init(
            title: object["title"]?.stringValue,
            truncated: truncated,
            total: total,
            shape: typedShape
        )
    }
}
