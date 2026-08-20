import Foundation

@main
struct PortableCoreCheck {
    static func expect(_ actual: String, _ expected: String, _ label: String) {
        guard actual == expected else {
            fputs("FAIL \(label): expected \(expected.debugDescription), got \(actual.debugDescription)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        expect(HostPathDisplay.abbreviateHomePath("/Users/u", home: "/Users/u"), "~", "exact POSIX home")
        expect(HostPathDisplay.abbreviateHomePath("/Users/u/Documents/project", home: "/Users/u"), "~/Documents/project", "POSIX descendant")
        expect(HostPathDisplay.abbreviateHomePath("/Users/u2/a.ts", home: "/Users/u"), "/Users/u2/a.ts", "POSIX prefix boundary")
        expect(HostPathDisplay.abbreviateHomePath("C:\\Users\\u\\project", home: "C:\\Users\\u"), "C:\\Users\\u\\project", "Windows drive path")
        expect(HostPathDisplay.abbreviateHomePath("\\\\server\\share\\u", home: "\\\\server\\share\\u"), "\\\\server\\share\\u", "UNC path")
        print("GlassPortableCore regression checks passed.")
    }
}
