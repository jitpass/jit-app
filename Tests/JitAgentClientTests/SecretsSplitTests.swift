// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Protect sheet shows jit's split and passes the user's changes back
/// as FILE:NAME flags. The app decides nothing else.
final class SecretsSplitTests: XCTestCase {
    private let home = "/Users/me"
    private let document = """
    {"files":[
      {"path":"/Users/me/code/billing-sync/.env","kind":"env","vars":[
        {"name":"BILLING_URL","class":"setting","in_vault":false,"value":"https://billing.example.com"},
        {"name":"BILLING_CLIENT_SECRET","class":"secret","in_vault":true},
        {"name":"OUTPUT_FILE_DEV_SECRETS","class":"check","in_vault":true},
        {"name":"KEEP_REPORTS","class":"setting","in_vault":false,"value":"30"}
      ]},
      {"path":"/Users/me/code/.mcp.json","kind":"mcp",
       "mcp":{"reads":["/Users/me/code/billing-sync/.env"],"inline_servers":0,"covered":true}}
    ]}
    """

    private func split() throws -> ProtectSplit {
        try ProtectSplit(preview: MigratePreview.parse(Data(document.utf8)))
    }

    func testDecodesAndCountsJitsSplit() throws {
        let s = try split()
        XCTAssertEqual(s.envFiles.count, 1)
        let file = s.envFiles[0]
        XCTAssertEqual(ScanWording.protectCardNote(s.counts(file)), "1 secret · 1 to check · 2 settings")
        XCTAssertEqual(ScanWording.protectSheetTitle(s, home: home), "Protect 2 files?")
        XCTAssertEqual(ScanWording.protectSheetSentence(s), "2 secrets go to the vault. 2 settings stay as they are, in plain text.")
        XCTAssertTrue(s.flags.isEmpty, "no change, no flags: jit's split stands")
        XCTAssertNil(file.vars?.first { $0.name == "BILLING_CLIENT_SECRET" }?.value, "a secret's value never reaches the app")
    }

    /// A moved line becomes one FILE:NAME flag, never a bare name that could
    /// reach a same-named variable in another file; moving it back drops it.
    func testAMovedLineIsOneQualifiedFlag() throws {
        var s = try split()
        let file = s.envFiles[0]
        let check = try XCTUnwrap(file.vars?.first { $0.name == "OUTPUT_FILE_DEV_SECRETS" })
        let url = try XCTUnwrap(file.vars?.first { $0.name == "BILLING_URL" })
        s.set(file: file.path, variable: check, inVault: false)
        s.set(file: file.path, variable: url, inVault: true)
        XCTAssertEqual(s.flags, [
            "--secret", "/Users/me/code/billing-sync/.env:BILLING_URL",
            "--setting", "/Users/me/code/billing-sync/.env:OUTPUT_FILE_DEV_SECRETS"
        ])
        XCTAssertEqual(ScanWording.protectCardNote(s.counts(file)), "2 secrets · 2 settings",
                       "a line the user chose is no longer one to check")
        s.set(file: file.path, variable: check, inVault: true)
        XCTAssertEqual(s.flags, ["--secret", "/Users/me/code/billing-sync/.env:BILLING_URL"])
    }

    func testCoveredMCPConfigNamesTheFile() throws {
        let mcp = try XCTUnwrap(split().preview.files[1].mcp)
        XCTAssertEqual(ScanWording.protectCoveredNote(mcp, home: home),
                       "Covered by billing-sync/.env above. It reads its secret from that file, so nothing else moves.")
    }

    /// Move Out asks the careful question unless the scan read the value and
    /// did not count it: a counted secret, and a value nobody checked.
    func testMoveOutRiskComesFromTheRecordedScan() throws {
        let json = """
        {"secrets":[
          {"path":"a/S","class":"dotenv","scan":"secret"},
          {"path":"a/C","class":"dotenv","scan":"check"},
          {"path":"a/U","class":"dotenv"}
        ],"backups":[]}
        """
        let listing = try JSONDecoder().decode(VaultListing.self, from: Data(json.utf8))
        XCTAssertEqual(listing.secrets.map(\.moveOutIsRisky), [true, false, true])
        XCTAssertEqual(listing.uncheckedFromEnv.map(\.path), ["a/U"])
    }

    /// An engine older than the split writes no settings field: still a
    /// report.
    func testOlderMigrateReportStillDecodes() throws {
        let old = #"{"targets":[],"applied":true,"vaulted":["X"],"caches":{"removed":[],"left":[]},"errors":[],"report":""}"#
        XCTAssertEqual(try MigrateReport.parse(old).settings, [])
        let new = #"{"targets":[],"applied":true,"vaulted":["X"],"settings":["p/URL"],"#
            + #""caches":{"removed":[],"left":[]},"errors":[],"report":""}"#
        XCTAssertEqual(try MigrateReport.parse(new).settings, ["p/URL"])
    }

    func testSettingsListingDecodes() throws {
        let json = #"{"settings":[{"path":"billing-sync/BILLING_URL","value":"https://billing.example.com","used_by":["billing-sync"]}]}"#
        let listing = try VaultSettingsListing.parse(Data(json.utf8))
        XCTAssertEqual(listing.settings.first?.group, "billing-sync")
        XCTAssertEqual(listing.settings.first?.name, "BILLING_URL")
    }

    /// What Changed says per file what went where, from the split the sheet
    /// showed; a covered MCP config says it had nothing to move.
    func testWhatChangedRowsSayWhereEachWent() throws {
        let s = try split()
        XCTAssertEqual(
            ChangeSheet.protectFact("/Users/me/code/billing-sync/.env", split: s),
            "2 in the vault · 2 settings kept as plain text"
        )
        XCTAssertEqual(
            ChangeSheet.protectFact("/Users/me/code/.mcp.json", split: s),
            "Nothing to move · its secret came from billing-sync/.env"
        )
        XCTAssertEqual(
            ChangeSheet.protectFact("/Users/me/code/billing-sync/.env", split: nil),
            "Backed up, then its secrets moved to the vault"
        )
    }
}
