import Foundation

/// Host-generation-scoped credential repository. Secret literals exist only as
/// call arguments and are never retained by the repository or UI projection.
actor CredentialRepository: NativeCredentialAPI {
    private let source: any NativeCredentialAPI

    init(source: any NativeCredentialAPI) {
        self.source = source
    }

    func describe(refs: [String]) async throws -> CredentialsDescribeResponse {
        try await source.describe(refs: refs)
    }

    func set(ref: String, value: String) async throws -> EmptyRPCResponse {
        try await source.set(ref: ref, value: value)
    }

    func unset(ref: String) async throws -> EmptyRPCResponse {
        try await source.unset(ref: ref)
    }
}
