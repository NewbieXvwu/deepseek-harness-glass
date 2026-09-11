import Foundation

protocol NativeSettingsAPI: Sendable {
    func describe() async throws -> SettingsDescribeResponse
    func mutate(
        namespace: String,
        operations: [SettingsPathOperationDTO],
        expectedRevision: Int?
    ) async throws -> SettingsNamespaceDTO
}

extension SettingsController: NativeSettingsAPI {}

/// Host-generation-scoped settings repository. The UI store owns observable
/// projection state; this repository owns Remote access and never stores drafts.
actor SettingsRepository: NativeSettingsAPI {
    private let source: any NativeSettingsAPI

    init(source: any NativeSettingsAPI) {
        self.source = source
    }

    func describe() async throws -> SettingsDescribeResponse {
        try await source.describe()
    }

    func mutate(
        namespace: String,
        operations: [SettingsPathOperationDTO],
        expectedRevision: Int?
    ) async throws -> SettingsNamespaceDTO {
        try await source.mutate(
            namespace: namespace,
            operations: operations,
            expectedRevision: expectedRevision
        )
    }
}
