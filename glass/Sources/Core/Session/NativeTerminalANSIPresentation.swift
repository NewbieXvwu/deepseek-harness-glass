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
        var lines: [[NativeTerminalANSISpan]] = [[]]
        var style = NativeTerminalANSIStyle()
        var visible = ""
        var requiresCursorReplay = false

        func appendVisible() {
            guard !visible.isEmpty else { return }
            let renderedStyle = style.isPlain ? nil : style
            if let last = lines[lines.count - 1].last, last.style == renderedStyle {
                lines[lines.count - 1].removeLast()
                lines[lines.count - 1].append(.init(text: last.text + visible, style: renderedStyle))
            } else {
                lines[lines.count - 1].append(.init(text: visible, style: renderedStyle))
            }
            visible = ""
        }

        let scalars = Array(rawOutput.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let value = scalar.value
            if value == 0x1B {
                appendVisible()
                guard index + 1 < scalars.count else {
                    index += 1
                    continue
                }
                let next = scalars[index + 1].value
                if next == 0x5D { // OSC: title/hyperlink, terminated by BEL or ST.
                    index += 2
                    while index < scalars.count {
                        if scalars[index].value == 0x07 {
                            index += 1
                            break
                        }
                        if scalars[index].value == 0x1B,
                           index + 1 < scalars.count,
                           scalars[index + 1].value == 0x5C {
                            index += 2
                            break
                        }
                        index += 1
                    }
                    continue
                }
                guard next == 0x5B else { // Non-CSI escape.
                    index += 2
                    while index < scalars.count, (0x20...0x2F).contains(scalars[index].value) {
                        index += 1
                    }
                    if index < scalars.count, (0x30...0x7E).contains(scalars[index].value) {
                        index += 1
                    }
                    continue
                }

                var cursor = index + 2
                while cursor < scalars.count, !(0x40...0x7E).contains(scalars[cursor].value) {
                    cursor += 1
                }
                guard cursor < scalars.count else {
                    break // Unterminated CSI is invisible rather than literal UI text.
                }
                let final = scalars[cursor].value
                let parameters = String(String.UnicodeScalarView(scalars[(index + 2)..<cursor]))
                if final == 0x6D { // m
                    style = folding(style: style, parameters: parameters)
                } else if final == 0x4B { // K
                    requiresCursorReplay = true
                }
                index = cursor + 1
                continue
            }
            if value == 0x0A {
                appendVisible()
                lines.append([])
                index += 1
                continue
            }
            if value == 0x0D || value == 0x08 {
                requiresCursorReplay = true
                index += 1
                continue
            }
            if isInertControl(value) {
                index += 1
                continue
            }
            visible.unicodeScalars.append(scalar)
            index += 1
        }
        appendVisible()
        return .init(lines: lines, requiresCursorReplay: requiresCursorReplay)
    }

    private static func isInertControl(_ scalar: UInt32) -> Bool {
        (0x00...0x07).contains(scalar)
            || (0x0B...0x1A).contains(scalar)
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
