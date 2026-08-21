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

    func testBatchRefreshRetainsEveryRequestedProviderCredentialView() async {
        let api = CredentialAPI(views: [
            "FIRST_KEY": .init(configured: true, source: "keychain", writable: true),
            "SECOND_KEY": .init(configured: false, source: nil, writable: true),
        ])
        let store = NativeCredentialStore()

        await store.refresh(refs: ["FIRST_KEY", "SECOND_KEY"], using: api)

        XCTAssertEqual(store.view(for: "FIRST_KEY")?.configured, true)
        XCTAssertEqual(store.view(for: "SECOND_KEY")?.configured, false)
        XCTAssertEqual(api.describeRequests, [["FIRST_KEY", "SECOND_KEY"]])
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

    func testLateCredentialDescribeCannotOverwriteNewerRequestedViewSet() async {
        let oldReached = expectation(description: "old credential describe reaches Host boundary")
        let api = DelayedCredentialAPI(oldReached: oldReached)
        let store = NativeCredentialStore()
        let oldTask = Task { await store.refresh(refs: ["OLD_KEY"], using: api) }
        await fulfillment(of: [oldReached], timeout: 1)

        await store.refresh(refs: ["NEW_KEY"], using: api)
        XCTAssertNil(store.view(for: "OLD_KEY"))
        XCTAssertEqual(store.view(for: "NEW_KEY")?.configured, true)

        await api.releaseOldDescribe()
        await oldTask.value
        XCTAssertNil(store.view(for: "OLD_KEY"))
        XCTAssertEqual(store.view(for: "NEW_KEY")?.configured, true)
    }

    private final class DelayedCredentialAPI: NativeCredentialAPI, @unchecked Sendable {
        let oldReached: XCTestExpectation
        private let gate = RecoveryGate()

        init(oldReached: XCTestExpectation) {
            self.oldReached = oldReached
        }

        func releaseOldDescribe() async {
            await gate.open()
        }

        func describe(refs: [String]) async throws -> CredentialsDescribeResponse {
            if refs == ["OLD_KEY"] {
                oldReached.fulfill()
                await gate.wait()
                return .init(credentials: ["OLD_KEY": .init(configured: false, source: nil, writable: true)])
            }
            return .init(credentials: ["NEW_KEY": .init(configured: true, source: "keychain", writable: true)])
        }
        func set(ref _: String, value _: String) async throws -> EmptyRPCResponse { throw DSHTransportError.invalidEndpoint }
        func unset(ref _: String) async throws -> EmptyRPCResponse { throw DSHTransportError.invalidEndpoint }
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
