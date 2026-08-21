import Foundation

@main
struct HostRuntimeLadderPortableCheck {
    static func main() throws {
        let ladder = HostRuntimeLadder(lockedBuildID: "dsh-v0.1.1-rc.1")
        let attach = HostRuntimeLadder.Candidate(kind: .attach(endpoint: URL(string: "http://127.0.0.1:7331/")!), buildID: "local-dev")
        let adopt = HostRuntimeLadder.Candidate(kind: .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh")), buildID: "dsh-v0.1.1-rc.1")
        let install = HostRuntimeLadder.Candidate(kind: .install, buildID: "dsh-v0.1.1-rc.1")
        try equal(ladder.select(attach: attach, adopt: adopt, install: install), .attach(endpoint: URL(string: "http://127.0.0.1:7331/")!, access: .readOnly(reason: "Attached Host build local-dev is not locked build dsh-v0.1.1-rc.1.")), "attach priority")
        try equal(ladder.select(attach: nil, adopt: adopt, install: install), .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh"), access: .verified), "adopt locked build")
        try equal(ladder.select(attach: nil, adopt: nil, install: install), .install(access: .verified), "install fallback")
        print("host runtime ladder portable check passed")
    }
    private static func equal<T: Equatable>(_ actual: T?, _ expected: T, _ label: String) throws { guard actual == expected else { throw Failure("\(label) failed") } }
}
private struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
