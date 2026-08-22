import Foundation


/// Source: `packages/client/runtime/src/client/workspaces/path.ts:abbreviateHomePath` at
/// `deepseek-ai/deepseek-harness@b150a551b8d465e31e418e1b2eaf5e79bbb7d28e`.
///
/// This is display-only: callers retain and copy the full Host-provided path.
/// POSIX home and its descendants use `~`; Windows drive and UNC paths remain
/// verbatim, matching the locked official UI rule.
public enum HostPathDisplay {
    public static func abbreviateHomePath(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        guard !isWindowsStylePath(path), !isWindowsStylePath(home) else { return path }

        let root = home.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !root.isEmpty else { return path }
        let normalizedRoot = "/" + root
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path

        if normalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == root {
            return "~"
        }
        if normalizedPath.hasPrefix(normalizedRoot + "/") {
            return "~" + String(normalizedPath.dropFirst(normalizedRoot.count))
        }
        return path
    }

    private static func isWindowsStylePath(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.hasPrefix("\\\\") { return true }
        let scalars = value.unicodeScalars
        guard scalars.count >= 3 else { return false }
        let first = scalars[scalars.startIndex]
        let second = scalars[scalars.index(after: scalars.startIndex)]
        let third = scalars[scalars.index(scalars.startIndex, offsetBy: 2)]
        return CharacterSet.letters.contains(first)
            && second == ":"
            && (third == "/" || third == "\\")
    }
}
