import XCTest
@testable import GlassCore

final class HostLoopbackEndpointDiscoveryTests: XCTestCase {
    func testCanonicalCandidatesRejectUnsafeEndpointsAndDeduplicate() {
        let discovery = HostLoopbackEndpointDiscovery()
        let candidates = [
            URL(string: "http://127.0.0.1:43123")!,
            URL(string: "http://127.0.0.1:43123/")!,
            URL(string: "http://localhost:43123/")!,
            URL(string: "http://user@127.0.0.1:43124/")!,
            URL(string: "http://127.0.0.1:43125/?x=1")!,
        ]
        XCTAssertEqual(discovery.canonicalCandidates(candidates), [URL(string: "http://127.0.0.1:43123/")!])
    }

    func testDiscoveryReturnsFirstDiagnosticsResponder() async {
        let discovery = HostLoopbackEndpointDiscovery()
        let first = URL(string: "http://127.0.0.1:43123/")!
        let second = URL(string: "http://127.0.0.1:43124/")!
        let found = await discovery.discover(candidates: [first, second], using: FixtureProbe(responsive: second))
        XCTAssertEqual(found, second)
    }

    private struct FixtureProbe: HostLoopbackEndpointDiscovery.Probe {
        let responsive: URL
        func respondsToDescribe(at endpoint: URL) async -> Bool { endpoint == responsive }
    }
}
