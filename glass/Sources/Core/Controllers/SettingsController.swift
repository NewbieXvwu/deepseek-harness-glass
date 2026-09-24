import Foundation

protocol SettingsControllerAPI: Sendable {
    func describe() async throws -> SettingsDescribeResponse
    func mutate(
        namespace: String,
        operations: [SettingsPathOperationDTO],
        expectedRevision: Int?
    ) async throws -> SettingsNamespaceDTO
}

struct SettingsController: SettingsControllerAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func describe() async throws -> SettingsDescribeResponse {
        try await remote.call(
            RemoteProcedure(.settingsDescribe),
            arguments: EmptyArguments()
        )
    }

    func mutate(
        namespace: String,
        operations: [SettingsPathOperationDTO],
        expectedRevision: Int?
    ) async throws -> SettingsNamespaceDTO {
        try await remote.call(
            RemoteProcedure(.settingsMutate),
            arguments: MutateArguments(
                ns: namespace,
                ops: operations,
                expectedRevision: expectedRevision
            )
        )
    }

    private struct EmptyArguments: Codable, Sendable {}

    private struct MutateArguments: Codable, Sendable {
        let ns: String
        let ops: [SettingsPathOperationDTO]
        let expectedRevision: Int?
    }
}
