// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class TouchIDAnswerTests: XCTestCase {
    /// Saying no to Touch ID is an answer, not a failure: the Vault shows
    /// "Not revealed" in grey for it, and red only for a real failure.
    func testACancelledPromptIsNotAFailure() {
        XCTAssertTrue(TouchIDAnswer.wasCancelled("jit: vault get: authentication canceled by user (LAErrorUserCancel)"))
        XCTAssertTrue(TouchIDAnswer.wasCancelled("Touch ID was cancelled"))
        XCTAssertFalse(TouchIDAnswer.wasCancelled("jit: vault get: billing-sync/BILLING_CLIENT_SECRET: secret not found"))
        XCTAssertFalse(TouchIDAnswer.wasCancelled("the service is not running"))
    }
}
