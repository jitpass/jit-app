// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// An action says what it did, in the window that shows it (2026-09-27):
/// a folder on screen is rescanned after a Protect, a scan the user
/// started says its failure, a wrap that failed after the vault changed
/// keeps what did change, and a reload asked during a read is kept.
final class ActionsSaidTests: XCTestCase {
    // MARK: - Scan landing

    func testAnActionsWholeMacRescanAlsoRescansTheFolderOnScreen() {
        for kind in [ScanRunKind.afterProtect, .deepAfterProtect] {
            let landing = ScanLanding(wholeMac: true, kind: kind, folderOnScreen: true)
            XCTAssertFalse(landing.showsReport, "a whole-Mac report never replaces a folder")
            XCTAssertTrue(landing.rescansFolder, "or the folder keeps the rows the action removed")
        }
    }

    func testOnlyAnActionsRescanRescansTheFolder() {
        XCTAssertFalse(ScanLanding(wholeMac: true, kind: .scheduled, folderOnScreen: true).rescansFolder)
        XCTAssertFalse(ScanLanding(wholeMac: true, kind: .afterProtect, folderOnScreen: false).rescansFolder)
        XCTAssertFalse(
            ScanLanding(wholeMac: false, kind: .afterProtect, folderOnScreen: true).rescansFolder,
            "the folder's own rescan stops there"
        )
    }

    func testAWholeMacScanTheUserStartedSaysItsFailure() {
        for kind in [ScanRunKind.byHand, .deep] {
            XCTAssertTrue(ScanLanding(wholeMac: true, kind: kind, folderOnScreen: false).saysFailure)
        }
    }

    func testAScheduledOrFollowUpScanKeepsItsFailureQuiet() {
        for kind in [ScanRunKind.scheduled, .afterProtect, .deepAfterProtect, .setup] {
            XCTAssertFalse(ScanLanding(wholeMac: true, kind: kind, folderOnScreen: false).saysFailure)
        }
        XCTAssertTrue(ScanLanding(wholeMac: false, kind: .afterProtect, folderOnScreen: true).saysFailure, "a folder always says")
    }

    // MARK: - Protect with a wrap that failed

    private let protected = MigrateReport(
        targets: ["/h/acme/.env"], applied: true, vaulted: ["ACME_TOKEN"], caches: .init(), errors: [], report: "moved ACME_TOKEN"
    )

    func testAWrapThatFailsAfterMigrateKeepsTheProtect() {
        let run = ProtectRun(
            reports: [protected],
            wrapFailure: .init(tool: "globex", line: "globex is not installed\n")
        )
        let outcome = run.outcome(home: "/h")
        XCTAssertEqual(
            outcome.title, "Protected ~/acme/.env · ACME_TOKEN is in the vault · wrap globex failed: globex is not installed"
        )
        XCTAssertTrue(outcome.failed)
        XCTAssertEqual(outcome.undo, ["/h/acme/.env"], "the file is in the vault, so Undo is offered")
        XCTAssertEqual(outcome.changes.files.map(\.path), ["/h/acme/.env"])
        let failure = outcome.changes.notes.first { $0.mark == .failed }
        XCTAssertEqual(failure?.name, "Wrapping globex failed")
        XCTAssertEqual(failure?.fact, "What changed here stays changed, and Undo still restores the files.")
        XCTAssertEqual(failure?.verbatim, "globex is not installed\n")
        XCTAssertTrue(outcome.text.contains("moved ACME_TOKEN"))
    }

    func testAWrapThatFailsAfterAnotherWrapSaysBothAndWhatWasNotTried() {
        let run = ProtectRun(
            wrapped: ["acme"], wrappedText: ["wrapped acme"],
            wrapFailure: .init(tool: "globex", line: "Touch ID was cancelled", notTried: ["initech"])
        )
        XCTAssertTrue(run.changedSomething)
        let outcome = run.outcome(home: "/h")
        XCTAssertEqual(outcome.title, "Wrapped acme · wrap globex failed: Touch ID was cancelled")
        XCTAssertEqual(outcome.undo, [])
        XCTAssertEqual(outcome.changes.title, "Protect did not finish")
        XCTAssertEqual(outcome.changes.notes.map(\.name), ["Wrapped acme", "Wrapping globex failed", "Not wrapped: initech"])
    }

    func testARunThatChangedNothingIsNotAPartialResult() {
        XCTAssertFalse(ProtectRun().changedSomething)
        var unapplied = protected
        unapplied.applied = false
        XCTAssertFalse(ProtectRun(reports: [unapplied]).changedSomething)
        XCTAssertTrue(ProtectRun(reports: [protected]).changedSomething)
    }

    func testAProtectWithEveryWrapDoneReadsAsBefore() {
        let outcome = ProtectRun(reports: [protected], wrapped: ["acme"], wrappedText: [""]).outcome(home: "/h")
        XCTAssertEqual(outcome.title, "Protected ~/acme/.env · ACME_TOKEN is in the vault · wrapped acme")
        XCTAssertFalse(outcome.failed)
        XCTAssertEqual(ProtectRun(wrapped: ["acme", "globex"], wrappedText: ["", ""]).outcome(home: "/h").title, "Wrapped 2 tools")
    }

    // MARK: - A wrap after a step that changed something

    func testAWrapThatFailsAfterItsFirstStepSaysWhatChanged() {
        let steps = WrapSteps(text: ["stored acme/ACME_TOKEN"], wrapFailed: "acme: no such command")
        XCTAssertTrue(steps.failed)
        XCTAssertEqual(
            steps.title(success: "Wrapped acme", done: "Protected ~/acme.rc", tool: "acme"),
            "Protected ~/acme.rc · wrap acme failed: acme: no such command"
        )
        XCTAssertEqual(steps.report, "stored acme/ACME_TOKEN\n\nacme: no such command")
    }

    func testAWrapThatWorkedSaysItsSuccess() {
        let steps = WrapSteps(text: ["stored", "wrapped"])
        XCTAssertFalse(steps.failed)
        XCTAssertEqual(steps.title(success: "Wrapped acme", done: "Protected ~/acme.rc", tool: "acme"), "Wrapped acme")
    }

    // MARK: - Reloads

    func testAReloadAskedDuringAReadRunsOnceItLands() {
        var gate = ReloadGate()
        XCTAssertTrue(gate.ask(), "nothing runs: start")
        XCTAssertFalse(gate.ask(), "one runs: wait")
        XCTAssertFalse(gate.ask(), "two asks, one more read")
        XCTAssertTrue(gate.landed(), "the waiting ask runs now")
        XCTAssertFalse(gate.ask(), "and it is running")
        XCTAssertTrue(gate.landed())
        XCTAssertFalse(gate.landed(), "nothing waits")
        XCTAssertTrue(gate.ask(), "idle again")
    }

    func testAReadWithNoAskDuringItJustLands() {
        var gate = ReloadGate()
        XCTAssertTrue(gate.ask())
        XCTAssertFalse(gate.landed())
        XCTAssertEqual(gate, ReloadGate())
    }

    func testTheVaultIsReadAgainWhereverItShows() {
        XCTAssertEqual(VaultRefresh.after(decoysOpen: true, vaultOpen: true, listed: true), .decoys)
        XCTAssertEqual(VaultRefresh.after(decoysOpen: false, vaultOpen: true, listed: false), .listing)
        XCTAssertEqual(VaultRefresh.after(decoysOpen: false, vaultOpen: false, listed: true), .listing, "the panel's vault row")
        XCTAssertEqual(VaultRefresh.after(decoysOpen: false, vaultOpen: false, listed: false), VaultRefresh.none)
    }

    // MARK: - AI Jobs

    func testARefusedDismissSaysTheProposalIsStillWaiting() {
        XCTAssertEqual(
            JobsWording.dismissFailed("acme-deploy", line: "the service is not running\n"),
            "Could not dismiss acme-deploy, so it is still waiting: the service is not running"
        )
        XCTAssertEqual(
            JobsWording.dismissFailed("acme-deploy", line: ""),
            "Could not dismiss acme-deploy, so it is still waiting: jit did not say why"
        )
    }
}
