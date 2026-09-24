import Foundation
import XCTest

@testable import GlassCore

final class HostDiagnosticRecorderTests: XCTestCase {
    func testConnectedHostWithoutOwnedPIDIsExternal() async throws {
        let recorder = HostDiagnosticRecorder(dshHome: "")
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:43123"))

        await recorder.recordConnected(endpoint: endpoint, pid: nil, generation: .init(rawValue: 3))
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(snapshot.ownership, "external")
        XCTAssertNil(snapshot.ownedProcessID)
        XCTAssertEqual(snapshot.port, 43123)
        XCTAssertEqual(snapshot.remoteGeneration, 3)
        XCTAssertEqual(snapshot.streamState, "ready")
    }
}
