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

    /// The agent's flag, read as it says: beside the Touch ID only when set,
    /// so an older agent's request still gets the sheet.
    func testTouchIDFollowsIsReadFromTheAgent() throws {
        XCTAssertFalse(try XCTUnwrap(ConsentRequest(event: pending())).touchIDFollows)
        XCTAssertTrue(try XCTUnwrap(ConsentRequest(event: pending(#","touch_id_follows":true"#))).touchIDFollows)
        XCTAssertFalse(try XCTUnwrap(ConsentRequest(event: pending(#","touch_id_follows":false"#))).touchIDFollows)
    }

    /// The app's own request beside a Touch ID is only marked shown, never
    /// put in the panel and never allowed; an older agent's request still
    /// gets the sheet, or the allow the app has always given its own.
    func testHandlingFollowsTheAgentsModeAndWhoAsked() throws {
        let beside = try XCTUnwrap(ConsentRequest(event: pending(#","touch_id_follows":true"#)))
        let first = try XCTUnwrap(ConsentRequest(event: pending()))
        XCTAssertEqual(beside.handling(ours: true), .markShown)
        XCTAssertEqual(beside.handling(ours: false), .showBeside)
        XCTAssertEqual(first.handling(ours: true), .allow)
        XCTAssertEqual(first.handling(ours: false), .showSheet)
    }

    /// Allowed only by an approval or the unlock it ends in; a denial, and
    /// anything the app does not know, says Denied.
    func testTheOutcomeIsReadFromTheAgentsKind() throws {
        var event = try pending()
        for (kind, allowed) in [("approved", true), ("unlock", true), ("denied", false), ("error", false)] {
            event.kind = kind
            XCTAssertEqual(ConsentRequest.allowed(by: event), allowed, kind)
        }
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

    /// `jit run --trust` and `jit run --with` ask under op reveal_pid too
    /// (agent/server.go), in the agent's own sentences (caller.go
    /// trustReason, grantReason): neither is "use a credential once".
    func testTrustAndAGlobalGrantSayWhatTheyGrant() throws {
        var event = try pending()
        event.cause = "let acmetool and everything it launches reach your credentials without further prompts"
        XCTAssertEqual(
            ConsentRequest(event: event)?.purpose,
            "trust a program: it and everything it launches reach your credentials without asking, until the vault locks"
        )
        event.cause = "grant this run access to your acme credentials file"
        XCTAssertEqual(ConsentRequest(event: event)?.purpose, "give this run a machine-wide credential file, for this run only")
    }

    /// On a locked vault the agent asks once for the credential and the
    /// unlock together (agent/consent.go unlockAsWell). The bold line must
    /// name the unlock: it is the larger authority, and the sub line alone
    /// used to carry it.
    func testACredentialPromptThatAlsoUnlocksSaysSo() throws {
        var event = try pending()
        event.cause = "use your aws credential and unlock the vault for terraform, via claude"
        let request = try XCTUnwrap(ConsentRequest(event: event))
        XCTAssertFalse(request.isUnlock)
        XCTAssertTrue(request.alsoUnlocks)
        XCTAssertEqual(request.purpose, "use a credential and unlock the vault: every secret it holds, until it locks again")

        event.cause = "grant this run access to your acme credentials file and unlock the vault"
        XCTAssertEqual(
            ConsentRequest(event: event)?.purpose,
            "give this run a machine-wide credential file and unlock the vault: every secret it holds, until it locks again"
        )

        event.cause = "use your aws credential for terraform, via claude"
        XCTAssertFalse(ConsentRequest(event: event)?.alsoUnlocks ?? true)
    }

    /// `jit grant --until-revoked` has no deadline (agent/grant.go).
    func testAStandingGrantHasNoDeadline() throws {
        var event = try pending()
        event.op = "grant_create"
        event.cause = "let acmetool use 2 secrets (acme) until you revoke it"
        XCTAssertEqual(ConsentRequest(event: event)?.purpose, "create a grant: unattended access until you revoke it")
        event.cause = "let acmetool use 2 secrets (acme) unattended for 1h"
        XCTAssertEqual(ConsentRequest(event: event)?.purpose, "create a grant: unattended access until a deadline")
    }
}
