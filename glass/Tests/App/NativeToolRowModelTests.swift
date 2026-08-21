import XCTest

@testable import GlassSpec
@testable import GlassUI

final class NativeToolRowModelTests: XCTestCase {
    func testFileToolSummaryUsesPathAndFilePathArgumentsBeforeRawJSON() {
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "write",
                arguments: #"{"file_path":"src/main.swift","content":"let value = 1"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "src/main.swift"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "edit",
                arguments: #"{"path":"README.md\nsecond line","old_string":"old"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "README.md"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "read",
                arguments: #"{"path":"first.md","file_path":"second.md"}"#,
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "first.md"
        )
    }

    func testFilePathAuthorityIsLimitedToOfficialFileToolArguments() {
        XCTAssertEqual(
            NativeToolRowModel.filePath(
                toolName: "write",
                arguments: #"{"file_path":"src/main.swift"}"#
            ),
            "src/main.swift"
        )
        XCTAssertEqual(
            NativeToolRowModel.filePath(
                toolName: "edit",
                arguments: #"{"path":"README.md"}"#
            ),
            "README.md"
        )
        XCTAssertNil(NativeToolRowModel.filePath(toolName: "bash", arguments: #"{"path":"script.sh"}"#))
        XCTAssertNil(NativeToolRowModel.filePath(toolName: "write", arguments: "partial request"))
    }

    func testToolSummaryFallsBackSafelyForMalformedAndGenericArguments() {
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "write",
                arguments: "partial request\nremaining",
                isGeneric: false,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "partial request"
        )
        XCTAssertEqual(
            NativeToolRowModel.summary(
                toolName: "custom_tool",
                arguments: "payload\nremaining",
                isGeneric: true,
                separator: OfficialUISpec.Text.toolSummarySeparator
            ),
            "custom_tool \(OfficialUISpec.Text.toolSummarySeparator) payload"
        )
    }
}
