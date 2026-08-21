import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeCredentialStoreTests: XCTestCase {
    func testRefreshRetainsOnlyRequestedHostCredentialViews() async {
        let api = CredentialAPI(
            views: [
                "SEARCH_KEY": .init(configured: true, source: "keychain", writable: true),
                "UNREQUESTED": .init(configured: true, source: "keychain", writable: true),
            ]
        )
        let store = NativeCredentialStore()

        await store.refresh(refs: ["SEARCH_KEY"], using: api)

        XCTAssertEqual(store.view(for: "SEARCH_KEY")?.configured, true)
        XCTAssertNil(store.view(for: "UNREQUESTED"))
    }

    func testSetAndUnsetConfirmStateOnlyThroughFreshHostDescribe() async {
        let api = CredentialAPI(views: ["SEARCH_KEY": .init(configured: false, source: nil, writable: true)])
        let store = NativeCredentialStore()

        XCTAssertTrue(await store.set(reference: "SEARCH_KEY", value: "test-secret", using: api))
        XCTAssertEqual(store.view(for: "SEARCH_KEY")?.configured, true)
        XCTAssertEqual(api.setReferences, ["SEARCH_KEY"])
        XCTAssertTrue(await store.unset(reference: "SEARCH_KEY", using: api))
        XCTAssertEqual(store.view(for: "SEARCH_KEY")?.configured, false)
        XCTAssertEqual(api.unsetReferences, ["SEARCH_KEY"])
        XCTAssertEqual(api.describeRequests, [["SEARCH_KEY"], ["SEARCH_KEY"]])
    }

    func testBlankOrRejectedWriteDoesNotManufactureCredentialState() async {
        let api = CredentialAPI(views: ["SEARCH_KEY": .init(configured: false, source: nil, writable: true)], rejectSet: true)
        let store = NativeCredentialStore()

        XCTAssertFalse(await store.set(reference: "SEARCH_KEY", value: "", using: api))
        XCTAssertFalse(await store.set(reference: "SEARCH_KEY", value: "test-secret", using: api))
        XCTAssertNil(store.view(for: "SEARCH_KEY"))
        XCTAssertTrue(api.setReferences.isEmpty)
    }

    private final class CredentialAPI: NativeCredentialAPI, @unchecked Sendable {
        private var views: [String: CredentialViewDTO]
        private let rejectSet: Bool
        private(set) var setReferences: [String] = []
        private(set) var unsetReferences: [String] = []
        private(set) var describeRequests: [[String]] = []

        init(views: [String: CredentialViewDTO], rejectSet: Bool = false) {
            self.views = views
            self.rejectSet = rejectSet
        }

        func describe(refs: [String]) async throws -> CredentialsDescribeResponse {
            describeRequests.append(refs)
            return .init(credentials: views)
        }

        func set(ref: String, value: String) async throws -> EmptyRPCResponse {
            if rejectSet { throw DSHTransportError.network("rejected") }
            setReferences.append(ref)
            views[ref] = .init(configured: true, source: "keychain", writable: true)
            return .init()
        }

        func unset(ref: String) async throws -> EmptyRPCResponse {
            unsetReferences.append(ref)
            views[ref] = .init(configured: false, source: nil, writable: true)
            return .init()
        }
    }
}
