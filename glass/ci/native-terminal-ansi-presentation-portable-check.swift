import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeTerminalANSIPresentationPortableCheck {
    static func main() throws {
        let styled = NativeTerminalANSIPresentation.parse("a\u{1B}[31mred\u{1B}[1m!\u{1B}[22m\nnext\u{1B}[0m plain")
        guard styled.lines.map({ $0.map(\.text) }) == [["a", "red", "!"], ["next", " plain"]],
              styled.lines[0][1].style?.foreground == .basic(.red),
              styled.lines[0][2].style?.bold == true,
              styled.lines[1][0].style?.foreground == .basic(.red),
              styled.lines[1][1].style == nil else {
            throw CheckFailure(description: "ANSI SGR state must form styled spans, close attributes, and thread through newlines")
        }

        let safe = NativeTerminalANSIPresentation.parse("\u{1B}]0;title\u{7}x\u{0}\t\n\u{1B}[38;5;208morange\u{1B}[48;2;1;2;3m bg")
        guard safe.lines.map({ $0.map(\.text).joined() }) == ["x\t", "orange bg"],
              safe.lines[1][0].style?.foreground == .palette(208),
              safe.lines[1][1].style?.background == .rgb(1, 2, 3),
              !safe.requiresCursorReplay,
              !safe.lines.flatMap({ $0 }).map(\.text).joined().contains("\u{1B}") else {
            throw CheckFailure(description: "ANSI projection must remove invisible controls while preserving visible layout and extended colors")
        }

        let replayed = NativeTerminalANSIPresentation.parse("100%\rOK\nloading...\rOK\u{1B}[K\nabc\u{8}Z")
        guard replayed.lines.map({ $0.map(\.text).joined() }) == ["OK0%", "OK", "abZ"],
              replayed.requiresCursorReplay else {
            throw CheckFailure(description: "terminal CR, erase-in-line and backspace must replay into the visible cell buffer")
        }
        print("native terminal ANSI presentation portable check passed")
    }
}
