import Foundation

import GlassPortableCore

/// Core owns the only raw-JSON adapter for the native terminal card. It rejects
/// all non-string/non-integral values instead of coercing plugin-defined wire
/// payloads into an official-looking terminal presentation.
extension ToolEventViewDTO {
    var nativeTerminalView: NativeToolTerminalView? {
        guard let object = view.objectValue,
              let card = object["card"]?.stringValue
        else { return nil }
        return NativeToolTerminalView(
            card: card,
            title: object["title"]?.stringValue,
            description: object["description"]?.stringValue,
            cwd: object["cwd"]?.stringValue,
            output: object["output"]?.stringValue,
            exitCode: integralExitCode(in: object["exitCode"]),
            signal: object["signal"]?.stringValue
        )
    }

    private func integralExitCode(in value: JSONValue?) -> Int? {
        guard let number = value?.numberValue,
              number.isFinite,
              number.rounded(.towardZero) == number,
              number >= Double(Int.min),
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}
