import Foundation
import XCTest
@testable import GlassCore

final class HostRuntimeLadderTests: XCTestCase {
    private let ladder = HostRuntimeLadder(lockedBuildID: "dsh-0.1.2-rc.1-official-a66e470")

    func testAttachWinsAndUnmatchedBuildIsReadOnly() {
        let attach = HostRuntimeLadder.Candidate(
            kind: .attach(endpoint: URL(string: "http://127.0.0.1:7331/")!),
            buildID: "local-dev"
        )
        let adopt = HostRuntimeLadder.Candidate(kind: .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh")), buildID: "dsh-0.1.2-rc.1-official-a66e470")
        XCTAssertEqual(
            ladder.select(attach: attach, adopt: adopt, install: nil),
            .attach(endpoint: URL(string: "http://127.0.0.1:7331/")!, access: .readOnly(reason: "Attached Host build local-dev is not locked build dsh-0.1.2-rc.1-official-a66e470."))
        )
    }

    func testAdoptIsVerifiedOnlyForLockedBuildAndInstallIsFinalFallback() {
        let adopt = HostRuntimeLadder.Candidate(kind: .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh")), buildID: "dsh-0.1.2-rc.1-official-a66e470")
        let install = HostRuntimeLadder.Candidate(kind: .install, buildID: "dsh-0.1.2-rc.1-official-a66e470")
        XCTAssertEqual(ladder.select(attach: nil, adopt: adopt, install: install), .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh"), access: .verified))
        XCTAssertEqual(ladder.select(attach: nil, adopt: nil, install: install), .install(access: .verified))
    }

    func testUnverifiedAdoptFallsBackToReadOnlyAndAllNilCandidatesFailClosed() {
        let unverified = HostRuntimeLadder.Candidate(kind: .adopt(executable: URL(fileURLWithPath: "/usr/local/bin/dsh")), buildID: "unverified-v1")
        XCTAssertEqual(
            ladder.select(attach: nil, adopt: unverified, install: nil),
            .adopt(
                executable: URL(fileURLWithPath: "/usr/local/bin/dsh"),
                access: .readOnly(reason: "Adopted Host build unverified-v1 is not locked build dsh-0.1.2-rc.1-official-a66e470.")
            )
        )
        XCTAssertNil(ladder.select(attach: nil, adopt: nil, install: nil))
    }
}
