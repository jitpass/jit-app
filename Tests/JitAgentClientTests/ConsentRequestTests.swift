// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class ConsentRequestTests: XCTestCase {
    private func pending(_ extra: String = "") throws -> SessionEvent {
        let json = #"{"unix_time":1789200000,"kind":"pending","op":"reveal_pid","consent_id":"ab12","# +
            #""by":"/opt/homebrew/bin/terraform apply -auto-approve","by_pid":4242,"launched_by":"claude","# +
            #""cause":"use your aws credential for terraform, via claude""# + extra + "}"
        return try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
    }

    func testReadsTheAgentsFactsOutOfThePendingEvent() throws {
        let request = try XCTUnwrap(ConsentRequest(event: pending()))
        XCTAssertEqual(request.id, "ab12")
        XCTAssertEqual(request.program, "terraform")
        XCTAssertEqual(request.command, "/opt/homebrew/bin/terraform apply -auto-approve")
        XCTAssertEqual(request.pid, 4242)
        XCTAssertEqual(request.launchedBy, "claude")
        XCTAssertEqual(request.headline, "use your aws credential for terraform, via claude")
        XCTAssertFalse(request.identifiedByScan)
        XCTAssertEqual(request.priorRefusals, 0)
        XCTAssertTrue(request.purpose.hasPrefix("use a credential"))
    }

    func testOnlyAPendingEventWithAnIDIsARequest() throws {
        var event = try pending()
        event.kind = "approved"
        XCTAssertNil(ConsentRequest(event: event))
        event.kind = "pending"
        event.consentID = nil
        XCTAssertNil(ConsentRequest(event: event))
    }

    func testScannedIdentityAndRefusalCountAreSurfaced() throws {
        let once = try XCTUnwrap(ConsentRequest(event: pending(#","by_likely":true"#)))
        XCTAssertTrue(once.identifiedByScan)

        var event = try pending()
        event.cause = "use your aws credential (refused once) for terraform"
        XCTAssertEqual(ConsentRequest(event: event)?.priorRefusals, 1)
        event.cause = "use your aws credential (refused 3 times) (identified by scan) for terraform"
        XCTAssertEqual(ConsentRequest(event: event)?.priorRefusals, 3)
    }

    func testNamesTheProcessWhenTheCommandIsUnknown() throws {
        var event = try pending()
        event.by = nil
        XCTAssertEqual(ConsentRequest(event: event)?.program, "a process (pid 4242)")
        event.byPID = nil
        XCTAssertEqual(ConsentRequest(event: event)?.program, "a program")
        event.op = "grant_create"
        XCTAssertTrue(ConsentRequest(event: event)?.purpose.hasPrefix("create a grant") ?? false)
    }

    func testAnUnlockIsToldApartByTheAgentsWording() throws {
        var event = try pending()
        event.op = "unwrap"
        event.cause = "unlock the vault for claude"
        let request = try XCTUnwrap(ConsentRequest(event: event))
        XCTAssertTrue(request.isUnlock)
        XCTAssertTrue(request.purpose.hasPrefix("unlock the vault"))
        event.cause = "use your aws credential for terraform"
        XCTAssertFalse(ConsentRequest(event: event)?.isUnlock ?? true)
    }
}
