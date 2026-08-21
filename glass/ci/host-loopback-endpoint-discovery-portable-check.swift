import Foundation

@main
struct HostLoopbackEndpointDiscoveryPortableCheck {
    static func main() async {
        let discovery = HostLoopbackEndpointDiscovery()
        let first = URL(string: "http://127.0.0.1:43123/")!
        let second = URL(string: "http://127.0.0.1:43124/")!
        precondition(discovery.canonicalCandidates([
            first,
            URL(string: "http://127.0.0.1:43123/")!,
            URL(string: "http://localhost:43125/")!,
            URL(string: "http://user@127.0.0.1:43126/")!,
        ]) == [first])
        let found = await discovery.discover(candidates: [first, second], using: FixtureProbe(responsive: second))
        precondition(found == second)
    }

    private struct FixtureProbe: HostLoopbackEndpointDiscovery.Probe {
        let responsive: URL
        func respondsToDescribe(at endpoint: URL) async -> Bool { endpoint == responsive }
    }
}
