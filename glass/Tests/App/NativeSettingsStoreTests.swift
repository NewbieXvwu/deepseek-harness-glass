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
