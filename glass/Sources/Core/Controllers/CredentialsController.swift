import Foundation

struct CredentialsController: NativeCredentialAPI, Sendable {
    private let remote: RemoteConnection

    init(remote: RemoteConnection) {
        self.remote = remote
    }

    func describe(refs: [String]) async throws -> CredentialsDescribeResponse {
        let credentials: [String: CredentialViewDTO] = try await remote.call(
            RemoteProcedure(.credentialsDescribe),
            arguments: DescribeArguments(refs: refs)
        )
        return CredentialsDescribeResponse(credentials: credentials)
    }

    func set(ref: String, value: String) async throws -> EmptyRPCResponse {
        try await remote.callNoValue(
            endpoint: .credentialsSet,
            arguments: SetArguments(ref: ref, value: value)
        )
        return EmptyRPCResponse()
    }

    func unset(ref: String) async throws -> EmptyRPCResponse {
        try await remote.callNoValue(
            endpoint: .credentialsUnset,
            arguments: UnsetArguments(ref: ref)
        )
        return EmptyRPCResponse()
    }

    private struct DescribeArguments: Codable, Sendable {
        let refs: [String]
    }

    private struct SetArguments: Codable, Sendable {
        let ref: String
        let value: String
    }

    private struct UnsetArguments: Codable, Sendable {
        let ref: String
    }
}
