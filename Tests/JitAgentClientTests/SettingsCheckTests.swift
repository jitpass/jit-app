// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class SettingsCheckTests: XCTestCase {
    /// The dry run's verdict, as the sheet shows it before anything moves:
    /// what it moved, and every other entry it read, which stays.
    func testWhatStaysIsEverythingTheCheckDidNotMove() throws {
        let json = #"{"read":4,"moved":["billing/BILLING_URL","billing/BILLING_CLIENT_ID"],"#
            + #""checks":["billing/BILLING_SECRET_FILE"],"skipped":[],"dry_run":true}"#
        let check = try MigrateSettingsResult.parse(json)
        let unchecked = ["billing/BILLING_CLIENT_ID", "billing/BILLING_CLIENT_SECRET", "billing/BILLING_SECRET_FILE", "billing/BILLING_URL"]
        let verdict = check.verdict(unchecked: unchecked)
        XCTAssertEqual(verdict.moves, ["billing/BILLING_CLIENT_ID", "billing/BILLING_URL"])
        XCTAssertEqual(verdict.stays, ["billing/BILLING_CLIENT_SECRET", "billing/BILLING_SECRET_FILE"])
        XCTAssertEqual(MigrateSettingsResult.dryRunArguments.prefix(3), ["migrate", "settings", "--dry-run"])
    }

    /// jit's candidates are every entry from a .env, some the app already
    /// saw checked: every path the button moves is listed, and no count goes
    /// below zero.
    func testAMoveOutsideTheUncheckedSetIsStillListed() throws {
        let json = #"{"read":2,"moved":["reports/REPORT_DIR","billing/BILLING_URL"],"checks":[],"skipped":[],"dry_run":true}"#
        let check = try MigrateSettingsResult.parse(json)
        let verdict = check.verdict(unchecked: ["billing/BILLING_URL"])
        XCTAssertEqual(verdict.moves, ["billing/BILLING_URL", "reports/REPORT_DIR"])
        XCTAssertEqual(verdict.stays, [])
        XCTAssertEqual(MigrateSettingsResult.byProfile(verdict.moves).map(\.0), ["billing", "reports"])
    }
}

final class VaultCommandLabelTests: XCTestCase {
    /// A sheet shows only its own command's state: a cancelled reveal's
    /// note, left behind, is not the settings sheet's.
    func testASheetShowsOnlyItsOwnCommand() {
        let owner = VaultCommandLabel.settingsCheck
        XCTAssertTrue(VaultCommandLabel.belongs(busy: owner, endedFor: nil, to: owner))
        XCTAssertTrue(VaultCommandLabel.belongs(busy: nil, endedFor: owner, to: owner))
        XCTAssertFalse(VaultCommandLabel.belongs(busy: nil, endedFor: "billing/BILLING_URL", to: owner))
        XCTAssertFalse(VaultCommandLabel.belongs(busy: "billing/BILLING_URL", endedFor: owner, to: owner))
        XCTAssertEqual(VaultCommandLabel.move(["billing/BILLING_URL"]), "billing/BILLING_URL")
        XCTAssertEqual(VaultCommandLabel.move(["a/A", "b/B"]), "2 values")
    }
}
