import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeSettingsStoreTests: XCTestCase {
    func testPermissionAuthorityClearsAfterDescribeFailureOrMissingFacade() async {
        let store = NativeSettingsStore()
        store.load(using: RecordingSettingsAPI(result: .success(.init(
            writable: true,
            hasDocument: true,
            namespaces: [permissionNamespace(value: "workspace-write", revision: 7)]
        ))))
        await eventually { store.phase == .ready }
        XCTAssertEqual(store.permissionPreset.status, .ready)
        XCTAssertTrue(store.permissionPreset.writable)
        XCTAssertEqual(store.permissionPreset.currentValue, "workspace-write")
        XCTAssertFalse(store.namespaces.isEmpty)

        store.load(using: RecordingSettingsAPI(result: .failure(URLError(.cannotConnectToHost))))
        await eventually {
            if case .failed = store.phase { return true }
            return false
        }
        XCTAssertFalse(store.writable)
        XCTAssertFalse(store.hasDocument)
        XCTAssertTrue(store.namespaces.isEmpty)
        XCTAssertEqual(store.permissionPreset.status, .unavailable)
        XCTAssertNil(store.permissionPreset.mutation(selecting: "workspace-write"))

        store.load(using: nil)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.permissionPreset.status, .unavailable)
    }

    func testRevisionConflictRetainsDraftAcrossRemoteRefreshAndRetriesWithLatestHostRevision() async throws {
        let original = permissionNamespace(value: "workspace-write", revision: 7)
        let remote = permissionNamespace(value: "workspace-write", revision: 8)
        let accepted = permissionNamespace(value: "danger-full-access", revision: 9)
        let api = ConflictThenAcceptingSettingsAPI(
            describes: [
                .init(writable: true, hasDocument: true, namespaces: [original]),
                .init(writable: true, hasDocument: true, namespaces: [remote]),
            ],
            accepted: accepted
        )
        let store = NativeSettingsStore()
        let operation = SettingsPathOperationDTO.set(
            path: ["defaultPreset"],
            value: .string("danger-full-access")
        )

        store.load(using: api)
        await eventually { store.namespaces.first?.revision == 7 }
        store.stage(namespace: original, operation: operation)
        XCTAssertTrue(store.isDirty(namespace: "permission"))

        do {
            try await store.saveDraft(namespace: "permission", using: api)
            XCTFail("an old Host revision must reject the first save")
        } catch {
            // The fake represents a second client committing revision 8 first.
        }
        XCTAssertEqual(api.expectedRevisions, [Optional(7)])
        XCTAssertEqual(store.namespaces.first?.revision, 7, "a rejected write must not invent a local namespace revision")
        XCTAssertEqual(store.drafts["permission"]?.operation, operation)

        store.load(using: api)
        await eventually { store.namespaces.first?.revision == 8 }
        XCTAssertEqual(store.drafts["permission"]?.operation, operation, "remote invalidation must preserve the correct local draft for repair or retry")

        try await store.saveDraft(namespace: "permission", using: api)
        XCTAssertEqual(api.expectedRevisions, [Optional(7), Optional(8)])
        XCTAssertEqual(store.namespaces.first, accepted)
        XCTAssertFalse(store.isDirty(namespace: "permission"), "only an accepted Host mutation may clear a staged draft")
    }

    private func eventually(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition was not met before timeout")
    }

    private func permissionNamespace(value: String, revision: Int) -> SettingsNamespaceDTO {
        .init(
            ns: "permission",
            schema: .object([
                "uid": .number(6),
                "refs": .object([
                    "1": .object(["type": .string("const"), "value": .string("read-only")]),
                    "2": .object(["type": .string("const"), "value": .string("workspace-write")]),
                    "4": .object(["type": .string("union"), "list": .array([.number(1), .number(2)])]),
                    "6": .object(["type": .string("object"), "dict": .object(["defaultPreset": .number(4)])]),
                ]),
            ]),
            value: .object(["defaultPreset": .string(value)]),
            base: nil,
            user: nil,
            applies: "live",
            secrets: [],
            revision: revision
        )
    }

    @MainActor
    private final class ConflictThenAcceptingSettingsAPI: NativeSettingsAPI {
        private var describes: [SettingsDescribeResponse]
        private let accepted: SettingsNamespaceDTO
        private(set) var expectedRevisions: [Int?] = []
        private var mutationCount = 0

        init(describes: [SettingsDescribeResponse], accepted: SettingsNamespaceDTO) {
            self.describes = describes
            self.accepted = accepted
        }

        func describe() async throws -> SettingsDescribeResponse {
            guard !describes.isEmpty else { throw URLError(.badServerResponse) }
            return describes.removeFirst()
        }

        func mutate(
            namespace _: String,
            operations _: [SettingsPathOperationDTO],
            expectedRevision: Int?
        ) async throws -> SettingsNamespaceDTO {
            expectedRevisions.append(expectedRevision)
            mutationCount += 1
            if mutationCount == 1 { throw URLError(.cannotWriteToFile) }
            return accepted
        }
    }

    @MainActor
    private final class RecordingSettingsAPI: NativeSettingsAPI {
        let result: Result<SettingsDescribeResponse, Error>

        init(result: Result<SettingsDescribeResponse, Error>) {
            self.result = result
        }

        func describe() async throws -> SettingsDescribeResponse {
            try result.get()
        }

        func mutate(
            namespace _: String,
            operations _: [SettingsPathOperationDTO],
            expectedRevision _: Int?
        ) async throws -> SettingsNamespaceDTO {
            throw URLError(.cannotConnectToHost)
        }
    }
}
