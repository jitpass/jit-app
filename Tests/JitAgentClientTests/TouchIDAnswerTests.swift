// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class TouchIDAnswerTests: XCTestCase {
    /// Saying no to Touch ID is an answer, not a failure: the Vault shows
    /// "Not revealed" in grey for it, and red only for a real failure.
    func testACancelledPromptIsNotAFailure() {
        XCTAssertTrue(TouchIDAnswer.wasCancelled("jit: vault get: authentication canceled by user (LAErrorUserCancel)"))
        XCTAssertTrue(TouchIDAnswer.wasCancelled("jit vault get: unwrapping data encryption key: local authentication failed: canceled"))
        XCTAssertTrue(TouchIDAnswer.wasCancelled("jit vault move-out: local authentication failed: Canceled by user."))
        XCTAssertFalse(TouchIDAnswer.wasCancelled("jit vault get: talking to the service: context canceled"),
                       "Go's context canceled is a failure, not an answer")
        XCTAssertFalse(TouchIDAnswer.wasCancelled("Touch ID was cancelled"), "no jit context: not trusted")
        XCTAssertFalse(TouchIDAnswer.wasCancelled("jit: vault get: billing-sync/BILLING_CLIENT_SECRET: secret not found"))
        XCTAssertFalse(TouchIDAnswer.wasCancelled("the service is not running"))
    }
}
