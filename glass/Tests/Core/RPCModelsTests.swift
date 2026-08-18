import XCTest

@testable import GlassCore

final class RPCModelsTests: XCTestCase {
    func testBusinessAndTransportErrorsHaveActionableDisposition() {
        let business: [(String, RPCErrorDisposition)] = [
            ("revision_conflict", .requiresRefresh),
            ("validation_invalid", .requiresUserCorrection),
            ("method_not_found", .unsupported),
            ("service_unavailable", .retryable),
            ("internal_error", .programFault),
        ]
        for (code, expected) in business {
            let error = RPCBusinessError(code: code, message: "fixture", details: .object([:]))
            XCTAssertEqual(error.disposition, expected, "business code \(code)")
        }

        let transport: [(DSHTransportError, RPCErrorDisposition)] = [
            (.timeout, .retryable),
            (.network("offline"), .retryable),
            (.invalidHTTPStatus(429, body: "busy"), .retryable),
            (.invalidHTTPStatus(503, body: "down"), .retryable),
            (.invalidHTTPStatus(400, body: "invalid"), .programFault),
            (.unverifiedHostBuild("fixture"), .unsupported),
            (.cancelled, .requiresUserCorrection),
            (.mismatchedRPCID(expected: "a", actual: "b"), .programFault),
            (.duplicateRPCID("rpc-fixture"), .programFault),
        ]
        for (error, expected) in transport {
            XCTAssertEqual(error.disposition, expected, "transport error \(error)")
        }
    }

    func testEnvelopePreservesRPCIDAndBusinessBranch() {
        let request = RPCClientRequest(rpcId: "rpc-fixture", method: "session.history", payload: .object([:]))
        let response = RPCServerResponse(
            type: "server-response",
            rpcId: "rpc-fixture",
            result: .failure(RPCBusinessError(code: "revision_conflict", message: "refresh", details: .object([:])))
        )
        let requestEnvelope = RPCEnvelope.clientRequest(request)
        let responseEnvelope = RPCEnvelope.serverResponse(response)
        XCTAssertEqual(requestEnvelope, .clientRequest(request))
        XCTAssertEqual(responseEnvelope, .serverResponse(response))
        XCTAssertEqual(response.rpcId, request.rpcId)
        guard case let .failure(error) = response.result else {
            XCTFail("fixture must preserve closed business error branch")
            return
        }
        XCTAssertEqual(error.disposition, .requiresRefresh)
    }
}
