import Foundation

extension ToolEventViewDTO {
    /// Strict wire admission for a result-side `card:'web'`. Optional text fields
    /// may be absent but may never change type silently.
    var nativeWebView: NativeToolWebView? {
        guard let object = view.objectValue,
              object["card"]?.stringValue == "web",
              let kind = object["kind"]?.stringValue,
              let truncated = object["truncated"]?.boolValue
        else { return nil }

        switch kind {
        case "search":
            let answer: String?
            if let value = object["answer"] {
                guard let string = value.stringValue else { return nil }
                answer = string
            } else {
                answer = nil
            }
            guard let values = object["sources"]?.arrayValue else { return nil }
            var sources: [NativeToolWebSource] = []
            sources.reserveCapacity(values.count)
            for value in values {
                guard let source = value.objectValue,
                      let url = source["url"]?.stringValue,
                      let title = optionalString(source["title"]),
                      let snippet = optionalString(source["snippet"]),
                      let publishedAt = optionalString(source["publishedAt"])
                else { return nil }
                sources.append(.init(url: url, title: title, snippet: snippet, publishedAt: publishedAt))
            }
            return .init(kind: .search(answer: answer, sources: sources, truncated: truncated))
        case "fetch":
            guard let url = object["url"]?.stringValue,
                  let statusCode = object["statusCode"]?.numberValue,
                  statusCode.isFinite
            else { return nil }
            return .init(kind: .fetch(url: url, statusCode: statusCode, truncated: truncated))
        default:
            return nil
        }
    }

    private func optionalString(_ value: JSONValue?) -> String?? {
        guard let value else { return .some(nil) }
        guard let string = value.stringValue else { return nil }
        return .some(string)
    }
}
