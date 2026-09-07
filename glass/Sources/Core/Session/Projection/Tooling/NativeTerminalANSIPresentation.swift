import Foundation

/// A normalized terminal color carried from an SGR run into the native renderer.
public enum NativeTerminalANSIColor: Equatable, Sendable {
    public enum Basic: String, Equatable, Sendable {
        case black, red, green, yellow, blue, magenta, cyan, white
        case brightBlack, brightRed, brightGreen, brightYellow
        case brightBlue, brightMagenta, brightCyan, brightWhite
    }

    case basic(Basic)
    case palette(Int)
    case rgb(Int, Int, Int)
}

/// The current SGR state for one visible ANSI text span.
public struct NativeTerminalANSIStyle: Equatable, Sendable {
    public var foreground: NativeTerminalANSIColor?
    public var background: NativeTerminalANSIColor?
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var hidden: Bool

    public init(
        foreground: NativeTerminalANSIColor? = nil,
        background: NativeTerminalANSIColor? = nil,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        hidden: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.hidden = hidden
    }

    public var isPlain: Bool {
        foreground == nil
            && background == nil
            && !bold
            && !dim
            && !italic
            && !underline
            && !strikethrough
            && !hidden
    }
}

public struct NativeTerminalANSISpan: Equatable, Sendable {
    public let text: String
    public let style: NativeTerminalANSIStyle?

    public init(text: String, style: NativeTerminalANSIStyle?) {
        self.text = text
        self.style = style
    }
}

/// The parsed visible terminal output. `requiresCursorReplay` records output
/// containing CR/backspace/erase-in-line; those controls never reach text UI.
public struct NativeTerminalANSIOutput: Equatable, Sendable {
    public let lines: [[NativeTerminalANSISpan]]
    public let requiresCursorReplay: Bool

    public init(lines: [[NativeTerminalANSISpan]], requiresCursorReplay: Bool) {
        self.lines = lines
        self.requiresCursorReplay = requiresCursorReplay
    }
}

/// Foundation-only subset of rc.2 `parseAnsiLines`. It is intentionally the
/// only raw-terminal control-sequence decoder. OSC, unsupported CSI and inert
/// controls are removed before UI consumption; SGR state is threaded across
/// line boundaries just as a terminal does.
public enum NativeTerminalANSIPresentation {
    public static func parse(_ rawOutput: String) -> NativeTerminalANSIOutput {
        let sanitized = sanitize(rawOutput)
        let rawLines = sanitized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var entryStyle = NativeTerminalANSIStyle()
        var replayRequired = false
        let lines = rawLines.map { rawLine -> [NativeTerminalANSISpan] in
            // A CR in CRLF only terminates a line; it must not redraw it.
            let line = rawLine.replacingOccurrences(of: "\\r+$", with: "", options: .regularExpression)
            let result = needsReplay(line)
                ? replayLine(line, entryStyle: entryStyle)
                : parsePlainLine(line, entryStyle: entryStyle)
            entryStyle = result.endingStyle
            replayRequired = replayRequired || result.replayed
            return result.spans
        }
        return .init(lines: lines, requiresCursorReplay: replayRequired)
    }

    private struct Cell {
        let style: NativeTerminalANSIStyle
        let text: String
        let spacer: Bool
    }

    private struct ReplayResult {
        let spans: [NativeTerminalANSISpan]
        let endingStyle: NativeTerminalANSIStyle
        let replayed: Bool
    }

    /// Mirrors rc.2 `sanitize`: OSC/non-CSI/inert controls disappear before any
    /// SwiftUI rendering, while CSI plus CR/backspace/tab survive for cell replay.
    private static func sanitize(_ rawOutput: String) -> String {
        let scalars = Array(rawOutput.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value != 0x1B {
                if !isInertControl(scalar.value) { output.append(scalar) }
                index += 1
                continue
            }
            guard index + 1 < scalars.count else { break }
            let next = scalars[index + 1].value
            if next == 0x5D { // OSC title/hyperlink, BEL or ST terminated.
                index += 2
                while index < scalars.count {
                    if scalars[index].value == 0x07 { index += 1; break }
                    if scalars[index].value == 0x1B,
                       index + 1 < scalars.count,
                       scalars[index + 1].value == 0x5C { index += 2; break }
                    index += 1
                }
                continue
            }
            guard next == 0x5B else { // non-CSI escape sequence
                index += 2
                while index < scalars.count, (0x20...0x2F).contains(scalars[index].value) { index += 1 }
                if index < scalars.count, (0x30...0x7E).contains(scalars[index].value) { index += 1 }
                continue
            }
            var end = index + 2
            while end < scalars.count, !(0x40...0x7E).contains(scalars[end].value) { end += 1 }
            guard end < scalars.count else { break }
            output.append(scalar)
            output.append(scalars[index + 1])
            for item in scalars[(index + 2)...end] { output.append(item) }
            index = end + 1
        }
        return String(output)
    }

    /// Direct rc.2 fast path for output that does not move a cursor. It keeps
    /// tabs as layout characters and folds only SGR state, avoiding per-cell
    /// allocations for large logs that never redraw a line.
    private static func parsePlainLine(_ line: String, entryStyle: NativeTerminalANSIStyle) -> ReplayResult {
        let scalars = Array(line.unicodeScalars)
        var style = entryStyle
        var spans: [NativeTerminalANSISpan] = []
        var visible = ""
        var index = 0
        func flush() {
            guard !visible.isEmpty else { return }
            let renderedStyle = style.isPlain ? nil : style
            if let last = spans.last, last.style == renderedStyle {
                spans.removeLast()
                spans.append(.init(text: last.text + visible, style: renderedStyle))
            } else {
                spans.append(.init(text: visible, style: renderedStyle))
            }
            visible = ""
        }
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x1B, index + 1 < scalars.count, scalars[index + 1].value == 0x5B {
                var end = index + 2
                while end < scalars.count, !(0x40...0x7E).contains(scalars[end].value) { end += 1 }
                guard end < scalars.count else { break }
                flush()
                if scalars[end].value == 0x6D {
                    style = folding(style: style, parameters: String(String.UnicodeScalarView(scalars[(index + 2)..<end])))
                }
                index = end + 1
                continue
            }
            visible.unicodeScalars.append(scalar)
            index += 1
        }
        flush()
        return .init(spans: spans, endingStyle: style, replayed: false)
    }

    private static func needsReplay(_ line: String) -> Bool {
        let scalars = Array(line.unicodeScalars)
        var index = 0
        while index < scalars.count {
            if scalars[index].value == 0x0D || scalars[index].value == 0x08 { return true }
            if scalars[index].value == 0x1B, index + 1 < scalars.count, scalars[index + 1].value == 0x5B {
                var end = index + 2
                while end < scalars.count, !(0x40...0x7E).contains(scalars[end].value) { end += 1 }
                if end < scalars.count, scalars[end].value == 0x4B { return true }
                index = end
            }
            index += 1
        }
        return false
    }

    private static func replayLine(_ line: String, entryStyle: NativeTerminalANSIStyle) -> ReplayResult {
        let scalars = Array(line.unicodeScalars)
        var cells: [Cell?] = []
        var cursor = 0
        var style = entryStyle
        var index = 0
        var replayed = false

        func ensureCell(_ cellIndex: Int) {
            while cells.count <= cellIndex { cells.append(nil) }
        }
        func isWideText(_ value: String) -> Bool {
            guard let scalar = value.unicodeScalars.first else { return false }
            let code = scalar.value
            return (0x1100...0x115F).contains(code)
                || (0x2E80...0xA4CF).contains(code)
                || (0xAC00...0xD7A3).contains(code)
                || (0xF900...0xFAFF).contains(code)
                || (0xFE10...0xFE6F).contains(code)
                || (0xFF01...0xFF60).contains(code)
                || (0xFFE0...0xFFE6).contains(code)
                || (0x1F300...0x1FAFF).contains(code)
        }
        func clear(_ cellIndex: Int, fill: String) {
            ensureCell(cellIndex)
            if cells[cellIndex]?.spacer == true, cellIndex > 0 {
                cells[cellIndex - 1] = .init(style: style, text: fill, spacer: false)
            } else if let existing = cells[cellIndex], isWideText(existing.text), cellIndex + 1 < cells.count, cells[cellIndex + 1]?.spacer == true {
                cells[cellIndex + 1] = .init(style: style, text: fill, spacer: false)
            }
            cells[cellIndex] = .init(style: style, text: fill, spacer: false)
        }
        func appendSpan(_ spans: inout [NativeTerminalANSISpan], text: String, style: NativeTerminalANSIStyle) {
            guard !text.isEmpty else { return }
            let renderedStyle = style.isPlain ? nil : style
            if let last = spans.last, last.style == renderedStyle {
                spans.removeLast()
                spans.append(.init(text: last.text + text, style: renderedStyle))
            } else {
                spans.append(.init(text: text, style: renderedStyle))
            }
        }

        while index < scalars.count {
            let scalar = scalars[index]
            let value = scalar.value
            if value == 0x1B, index + 1 < scalars.count, scalars[index + 1].value == 0x5B {
                var end = index + 2
                while end < scalars.count, !(0x40...0x7E).contains(scalars[end].value) { end += 1 }
                guard end < scalars.count else { break }
                let parameters = String(String.UnicodeScalarView(scalars[(index + 2)..<end]))
                switch scalars[end].value {
                case 0x6D: // m
                    style = folding(style: style, parameters: parameters)
                case 0x4B: // K
                    replayed = true
                    let mode = parameters.split(separator: ";", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    if mode == "1" {
                        for erased in 0...cursor { clear(erased, fill: " ") }
                    } else if mode == "2" {
                        cells.removeAll()
                    } else if cursor < cells.count {
                        cells.removeSubrange(cursor..<cells.count)
                    }
                default:
                    break
                }
                index = end + 1
                continue
            }
            if value == 0x0D { cursor = 0; replayed = true; index += 1; continue }
            if value == 0x08 { cursor = max(0, cursor - 1); replayed = true; index += 1; continue }
            if value == 0x09 {
                replayed = true
                let stop = cursor + 8 - (cursor % 8)
                while cursor < stop {
                    ensureCell(cursor)
                    if cells[cursor] == nil { cells[cursor] = .init(style: style, text: " ", spacer: false) }
                    cursor += 1
                }
                index += 1
                continue
            }
            if isZeroWidth(scalar) {
                if cursor > 0, let previous = cells[cursor - 1] {
                    cells[cursor - 1] = .init(style: previous.style, text: previous.text + String(scalar), spacer: previous.spacer)
                }
                index += 1
                continue
            }
            clear(cursor, fill: " ")
            let text = String(scalar)
            cells[cursor] = .init(style: style, text: text, spacer: false)
            cursor += 1
            if isWideText(text) {
                ensureCell(cursor)
                cells[cursor] = .init(style: style, text: "", spacer: true)
                cursor += 1
            }
            index += 1
        }

        var spans: [NativeTerminalANSISpan] = []
        for cellIndex in cells.indices {
            let cell = cells[cellIndex] ?? .init(style: .init(), text: " ", spacer: false)
            let leadIsWide = cellIndex > 0 && isWideText(cells[cellIndex - 1]?.text ?? "")
            appendSpan(&spans, text: cell.spacer && !leadIsWide ? " " : cell.text, style: cell.style)
        }
        return .init(spans: spans, endingStyle: style, replayed: replayed)
    }

    private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return true
        default:
            return (0x200B...0x200F).contains(scalar.value) || scalar.value == 0x2060
        }
    }

    private static func isInertControl(_ scalar: UInt32) -> Bool {
        (0x00...0x07).contains(scalar)
            || ((0x0B...0x1A).contains(scalar) && scalar != 0x0D)
            || (0x1C...0x1F).contains(scalar)
            || scalar == 0x7F
    }

    private static func folding(style: NativeTerminalANSIStyle, parameters: String) -> NativeTerminalANSIStyle {
        let codes = parameters.isEmpty ? ["0"] : parameters.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var next = style
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case "", "0":
                next = .init()
            case "1": next.bold = true
            case "2": next.dim = true
            case "3": next.italic = true
            case "4": next.underline = true
            case "9": next.strikethrough = true
            case "8": next.hidden = true
            case "22": next.bold = false; next.dim = false
            case "23": next.italic = false
            case "24": next.underline = false
            case "28": next.hidden = false
            case "29": next.strikethrough = false
            case "39": next.foreground = nil
            case "49": next.background = nil
            case "30"..."37", "90"..."97": next.foreground = basicColor(code)
            case "40"..."47", "100"..."107": next.background = basicColor(String(Int(code)! - 10))
            case "38", "48":
                let color = extendedColor(codes: codes, start: index)
                if let color {
                    if code == "38" { next.foreground = color.color } else { next.background = color.color }
                    index = color.endIndex
                }
            default:
                break
            }
            index += 1
        }
        return next
    }

    private static func extendedColor(codes: [String], start: Int) -> (color: NativeTerminalANSIColor, endIndex: Int)? {
        guard start + 2 < codes.count else { return nil }
        switch codes[start + 1] {
        case "5":
            guard let palette = Int(codes[start + 2]), (0...255).contains(palette) else { return nil }
            return (.palette(palette), start + 2)
        case "2":
            guard start + 4 < codes.count,
                  let red = Int(codes[start + 2]),
                  let green = Int(codes[start + 3]),
                  let blue = Int(codes[start + 4]),
                  (0...255).contains(red),
                  (0...255).contains(green),
                  (0...255).contains(blue)
            else { return nil }
            return (.rgb(red, green, blue), start + 4)
        default:
            return nil
        }
    }

    private static func basicColor(_ code: String) -> NativeTerminalANSIColor? {
        let colors: [String: NativeTerminalANSIColor.Basic] = [
            "30": .black, "31": .red, "32": .green, "33": .yellow,
            "34": .blue, "35": .magenta, "36": .cyan, "37": .white,
            "90": .brightBlack, "91": .brightRed, "92": .brightGreen, "93": .brightYellow,
            "94": .brightBlue, "95": .brightMagenta, "96": .brightCyan, "97": .brightWhite,
        ]
        return colors[code].map(NativeTerminalANSIColor.basic)
    }
}
