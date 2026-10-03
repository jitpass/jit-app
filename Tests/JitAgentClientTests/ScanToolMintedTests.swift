// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// jit's `tool_minted` (schema 0.26.0): a login a tool writes and renews
/// itself. Outside the summary's counts, so outside Needs you, the panel
/// and the news; shown in its own card, in jit's words.
final class ScanToolMintedTests: XCTestCase {
    private let gke = #"""
    {"record_type":"finding","record_id":"m1","finding_type":"credential_file","severity":"medium",
     "file_path":"/Users/me/.kube/gke_gcloud_auth_plugin_cache","evidence":"GKE auth plugin token cache","remedy":"manual",
     "archived":false,"test_fixture":false,
     "tool_minted":{"title":"The GKE auth plugin's token cache (renews itself)",
                    "advice":"nothing to rotate; `gcloud auth revoke` ends the login behind it"}}
    """#

    private let stripe = #"""
    {"record_type":"finding","record_id":"s1","finding_type":"exposed_secret","severity":"high",
     "file_path":"/Users/me/notes.txt","line":3,"evidence":"value matches Stripe API Key's known token format",
     "remedy":"manual","archived":false,"test_fixture":false}
    """#

    /// One finding per line (NDJSON), then a summary.
    private func report(_ findings: [String]) throws -> ScanReport {
        let lines = findings.map { $0.replacingOccurrences(of: "\n", with: " ") }
        let summary = #"{"record_type":"scan_summary","total_findings":1,"risk_level":"high","exposure_score":0,"#
            + #""secrets_total":1,"secrets_protected":0,"secrets_migratable":0,"files_scanned":2}"#
        return try ScanReport.parse(Data((lines + [summary]).joined(separator: "\n").utf8))
    }

    func testASelfRenewingLoginHasItsOwnCardNotNeedsYou() throws {
        let scan = try report([gke, stripe])
        XCTAssertEqual(scan.findings.first?.toolMinted?.title, "The GKE auth plugin's token cache (renews itself)")
        XCTAssertEqual(scan.manual.map(\.id), ["s1"], "Needs you keeps only what the reader must rotate")
        XCTAssertEqual(scan.groups(in: .rotatesItself).map(\.filePath), ["/Users/me/.kube/gke_gcloud_auth_plugin_cache"])
        XCTAssertEqual(scan.tiersPresent, [.needsYou, .rotatesItself])
    }

    func testTheRowSaysWhatItIsAndWhatToDoInJitsWords() throws {
        let group = try XCTUnwrap(report([gke]).groups(in: .rotatesItself).first)
        XCTAssertEqual(
            group.fact,
            "The GKE auth plugin's token cache (renews itself) · nothing to rotate; gcloud auth revoke ends the login behind it"
        )
    }

    func testASelfRenewingLoginIsNeverNewsOrAToDo() throws {
        let scan = try report([gke])
        XCTAssertEqual(scan.newFindings(known: []).map(\.id), [], "a renewed cache is not news")
        XCTAssertEqual(scan.todos(deepAvailable: false).map(\.text), ["Nothing in the open."], "nothing for the header to ask")
    }

    /// An engine before 0.26.0 sends no tool_minted: the finding stays a
    /// Needs-you row, as it always was.
    func testWithoutTheFieldAManualFindingStaysNeedsYou() throws {
        let scan = try report([stripe])
        XCTAssertNil(scan.findings.first?.toolMinted)
        XCTAssertEqual(scan.tiersPresent, [.needsYou])
    }
}
