import Foundation


/// Source: `packages/client/runtime/src/client/workspaces/path.ts:abbreviateHomePath` at
/// `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534`.
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
        let normalizedPath = path.hasPrefix("/") ? path : path

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
        let scalars = Array(value.unicodeScalars)
        return scalars.count >= 3
            && CharacterSet.letters.contains(scalars[0])
            && scalars[1].value == 58
            && (scalars[2].value == 47 || scalars[2].value == 92)
    }
}
