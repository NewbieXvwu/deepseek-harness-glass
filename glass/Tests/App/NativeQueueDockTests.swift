import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeQueueDockTests: XCTestCase {
    func testFiltersSteeringAndContextRowsAndRequiresExplicitNormalSessionForActions() {
        let rows = [
            row(id: "queued", placement: .queued),
            row(id: "steering", placement: .steering),
            row(id: "context", placement: .context),
        ]
        XCTAssertEqual(NativeQueueDockPresentation.queuedRows(rows).map(\.id), ["queued"])
        XCTAssertTrue(NativeQueueDockPresentation.isMutable(.noValidDescriptor))
        XCTAssertFalse(NativeQueueDockPresentation.isMutable(.absent))
        XCTAssertFalse(NativeQueueDockPresentation.isMutable(.identity(.init(mode: .continuable, label: "child", descriptorSeq: 1))))
    }

    func testFailureCopyIsScopedToAddressedRowAndOfficialActionKind() {
        let failure = NativeSessionStore.QueueActionFailure(itemID: "row-1", kind: .remove)
        XCTAssertEqual(NativeQueueDockPresentation.failureText(failure, rowID: "row-1"), OfficialUISpec.Text.queueRemoveFailure)
        XCTAssertNil(NativeQueueDockPresentation.failureText(failure, rowID: "row-2"))
    }

    private func row(id: String, placement: NativeSessionStore.QueuedMessage.Placement) -> NativeSessionStore.QueuedMessage {
        .init(
            id: id,
            messageID: "message-\(id)",
            placement: placement,
            role: "user",
            content: [.object(["type": .string("text"), "text": .string("queued body")])],
            source: .null,
            preview: "queued body",
            text: "queued body"
        )
    }
}
