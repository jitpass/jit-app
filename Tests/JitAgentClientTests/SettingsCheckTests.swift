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
        let all = ["billing/BILLING_CLIENT_ID", "billing/BILLING_CLIENT_SECRET", "billing/BILLING_SECRET_FILE", "billing/BILLING_URL"]
        XCTAssertEqual(check.stays(of: all), ["billing/BILLING_CLIENT_SECRET", "billing/BILLING_SECRET_FILE"])
        XCTAssertEqual(MigrateSettingsResult.dryRunArguments.prefix(3), ["migrate", "settings", "--dry-run"])
    }
}
