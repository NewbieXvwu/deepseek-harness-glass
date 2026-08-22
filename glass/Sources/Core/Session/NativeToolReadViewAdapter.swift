import Foundation

/// The only raw-JSON adapter for the official read result card. It preserves a
/// strict typed boundary: unknown card tags can exist as raw event data, but an
/// incomplete or malformed read envelope never becomes an official-looking
/// read card.
extension ToolEventViewDTO {
    var nativeReadView: NativeToolReadView? {
        guard let object = view.objectValue,
              let card = object["card"]?.stringValue,
              card == "read",
              let path = object["path"]?.stringValue,
              let linesValue = object["lines"]?.arrayValue,
              let totalLines = nonNegativeInteger(object["totalLines"])
        else { return nil }

        var lines: [NativeToolReadLine] = []
        lines.reserveCapacity(linesValue.count)
        for value in linesValue {
            guard let line = value.objectValue,
                  let number = positiveInteger(line["number"]),
                  let text = line["text"]?.stringValue
            else { return nil }
            lines.append(.init(number: number, text: text))
        }
        guard totalLines >= lines.count else { return nil }
        return NativeToolReadView(
            card: card,
            title: object["title"]?.stringValue,
            path: path,
            lines: lines,
            totalLines: totalLines,
            lang: object["lang"]?.stringValue
        )
    }

    private func positiveInteger(_ value: JSONValue?) -> Int? {
        guard let integer = integral(value), integer >= 1 else { return nil }
        return integer
    }

    private func nonNegativeInteger(_ value: JSONValue?) -> Int? {
        guard let integer = integral(value), integer >= 0 else { return nil }
        return integer
    }

    private func integral(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue,
              number.isFinite,
              number.rounded(.towardZero) == number,
              number >= Double(Int.min),
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}
