import Foundation
import XCTest

@testable import GlassCore

final class HostLaunchDescriptorTests: XCTestCase {
    func testAcceptsOnlyRootLoopbackProcessTokenURLAndProducesCleanBaseURL() throws {
        let descriptor = try HostLaunchDescriptor(
            url: XCTUnwrap(URL(string: "http://127.0.0.1:43123/?token=process-secret"))
        )
        XCTAssertEqual(descriptor.launchURL.absoluteString, "http://127.0.0.1:43123/?token=process-secret")
        XCTAssertEqual(descriptor.cleanBaseURL.absoluteString, "http://127.0.0.1:43123/")
    }

    func testRejectsMalformedLaunchAuthoritiesPathsPortsAndTokens() throws {
        let invalidURLs = [
            "https://127.0.0.1:43123/?token=secret",
            "http://localhost:43123/?token=secret",
            "http://user@127.0.0.1:43123/?token=secret",
            "http://127.0.0.1:0/?token=secret",
            "http://127.0.0.1:43123/api?token=secret",
            "http://127.0.0.1:43123/?token=secret#fragment",
        ]
        for rawURL in invalidURLs {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertThrowsError(try HostLaunchDescriptor(url: url), rawURL)
        }

        let missingTokenURLs = [
            "http://127.0.0.1:43123/",
            "http://127.0.0.1:43123/?token=",
            "http://127.0.0.1:43123/?other=secret",
            "http://127.0.0.1:43123/?token=one&token=two",
        ]
        for rawURL in missingTokenURLs {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertThrowsError(try HostLaunchDescriptor(url: url), rawURL) { error in
                XCTAssertEqual(error as? HostLaunchDescriptorError, .missingProcessToken)
            }
        }
    }
}
