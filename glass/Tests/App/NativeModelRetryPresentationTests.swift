import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

final class NativeModelRetryPresentationTests: XCTestCase {
    func testScheduledAttemptUsesOfficialCountdownAndFiniteMaximum() {
        let attempt = fixture(state: .scheduled, delayMilliseconds: 1_250, maximumRetries: 3)

        XCTAssertEqual(NativeModelRetryPresentation.scheduledSeconds(for: attempt), 2)
        XCTAssertEqual(NativeModelRetryPresentation.label(for: .scheduled), OfficialUISpec.Text.retryScheduled)
        XCTAssertEqual(
            NativeModelRetryPresentation.status(attempt),
            OfficialUISpec.Text.retryStatus(label: OfficialUISpec.Text.retryScheduled, retry: 2, maximum: "3", seconds: 2)
        )
    }

    func testStartedAndCancelledAttemptsUseOfficialStateWithoutCountdownDrift() {
        let started = fixture(state: .started, delayMilliseconds: 1_250, maximumRetries: 3)
        let cancelled = fixture(state: .cancelled, delayMilliseconds: 1_250, maximumRetries: nil, unlimited: true)

        XCTAssertEqual(NativeModelRetryPresentation.label(for: .started), OfficialUISpec.Text.retryStarted)
        XCTAssertEqual(NativeModelRetryPresentation.label(for: .cancelled), OfficialUISpec.Text.retryCancelled)
        XCTAssertEqual(
            NativeModelRetryPresentation.status(started),
            OfficialUISpec.Text.retryStatus(label: OfficialUISpec.Text.retryStarted, retry: 2, maximum: "3", seconds: 2)
        )
        XCTAssertEqual(
            NativeModelRetryPresentation.status(cancelled),
            OfficialUISpec.Text.retryStatus(label: OfficialUISpec.Text.retryCancelled, retry: 2, maximum: "∞", seconds: 2)
        )
    }

    private func fixture(
        state: CoreRetryAttempt.State,
        delayMilliseconds: Int,
        maximumRetries: Int?,
        unlimited: Bool = false
    ) -> CoreRetryAttempt {
        .init(
            seq: 7,
            time: 7,
            retry: 2,
            state: state,
            delayMilliseconds: delayMilliseconds,
            failureMessage: "Host busy",
            maximumRetries: maximumRetries,
            unlimited: unlimited
        )
    }
}
