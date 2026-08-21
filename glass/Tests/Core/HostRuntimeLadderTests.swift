import Foundation
import XCTest
@testable import GlassCore

final class HostRuntimeLadderTests: XCTestCase {
    private let ladder = HostRuntimeLadder(lockedBuildID: "dsh-v0.1.1-rc.1")

    func testAttachWinsAndUnmatchedBuildIsReadOnly() {
        let attach = HostRuntimeLadder.Candidate(
            kind: .attach(endpoint: URL(string: "http://127.0.0.1:7331/")!),
            buildID: "local-dev"
        )
        let adopt = HostRuntimeLadder.Candidate(kind: .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh")), buildID: "dsh-v0.1.1-rc.1")
        XCTAssertEqual(
            ladder.select(attach: attach, adopt: adopt, install: nil),
            .attach(endpoint: URL(string: "http://127.0.0.1:7331/")!, access: .readOnly(reason: "Attached Host build local-dev is not locked build dsh-v0.1.1-rc.1."))
        )
    }

    func testAdoptIsVerifiedOnlyForLockedBuildAndInstallIsFinalFallback() {
        let adopt = HostRuntimeLadder.Candidate(kind: .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh")), buildID: "dsh-v0.1.1-rc.1")
        let install = HostRuntimeLadder.Candidate(kind: .install, buildID: "dsh-v0.1.1-rc.1")
        XCTAssertEqual(ladder.select(attach: nil, adopt: adopt, install: install), .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh"), access: .verified))
        XCTAssertEqual(ladder.select(attach: nil, adopt: nil, install: install), .install(access: .verified))
    }
}
