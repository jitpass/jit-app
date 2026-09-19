// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class VaultDuplicatesTests: XCTestCase {
    func testDecodesVerdictsAndPrunablePaths() throws {
        let json = #"""
        {"findings":[
          {"groups":["a","a-copy"],"keys":["KEY"],"origins":["~/p/.env","~/q/.env"],"same_origin":false,"values_match":true,
           "remove_group":"a-copy","remove_command":"jit vault rm a-copy","prunable":true,"remove_paths":["a-copy/KEY"]},
          {"groups":["b","b2"],"keys":["X","Y"],"origins":["~/b/.env","~/b/.env"],"same_origin":true,
           "values_match":false,"differ_keys":["Y"]},
          {"groups":["c","c2"],"keys":["X"],"origins":["",""],"same_origin":false,"values_match":true,"extra_keys":["Z"]}
        ],"shared_credentials":[{"keys":["TOKEN"],"groups":["s1","s2"]}],"secrets_compared":67}
        """#
        let report = try JSONDecoder().decode(VaultDuplicates.self, from: Data(json.utf8))
        XCTAssertEqual(report.secretsCompared, 67)
        XCTAssertEqual(report.findings.count, 3)
        XCTAssertEqual(report.prunablePaths, ["a-copy/KEY"])
        XCTAssertTrue(report.findings[0].verdict.contains("stale copy"))
        XCTAssertTrue(report.findings[1].verdict.contains("values differ (Y)"))
        XCTAssertTrue(report.findings[2].verdict.contains("Z only in some copies"))
        XCTAssertEqual(report.sharedCredentials.first?.groups, ["s1", "s2"])
    }

    func testEmptyReportDecodes() throws {
        let report = try JSONDecoder().decode(
            VaultDuplicates.self,
            from: Data(#"{"findings":[],"shared_credentials":[],"secrets_compared":0}"#.utf8)
        )
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertTrue(report.prunablePaths.isEmpty)
    }
}

extension VaultDuplicatesTests {
    /// jit 1.9: a stale-looking copy something still uses gets no removal
    /// at all, and the sheet says who uses it.
    func testInUseCopyIsNamedNeverPruned() throws {
        let json = #"""
        {"findings":[
          {"groups":["mcp-okta","mcp-okta-2"],"keys":["TOKEN"],"origins":["~/gone/.mcp.json","~/gone/.mcp.json"],
           "origin_gone":[true,true],"same_origin":true,"values_match":true,"prunable":false,
           "in_use_group":"mcp-okta-2","in_use_profiles":["mcp-okta-2"],"in_use_pointer_files":["~/.clisso.yaml"],"future":1}
        ],"shared_credentials":[],"secrets_compared":2}
        """#
        let report = try JSONDecoder().decode(VaultDuplicates.self, from: Data(json.utf8))
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.inUseGroup, "mcp-okta-2")
        XCTAssertEqual(finding.inUseProfiles, ["mcp-okta-2"])
        XCTAssertEqual(finding.inUsePointerFiles, ["~/.clisso.yaml"])
        XCTAssertEqual(finding.originGone, [true, true])
        XCTAssertEqual(finding.groupLabels, ["mcp-okta (origin gone)", "mcp-okta-2 (origin gone)"])
        XCTAssertTrue(finding.verdict.contains("in use by profile mcp-okta-2 and ~/.clisso.yaml"), finding.verdict)
        XCTAssertTrue(report.prunablePaths.isEmpty)
        XCTAssertNil(report.pruneConfirmation().button)
    }

    func testPruneConfirmationNamesThePaths() throws {
        let json = #"""
        {"findings":[{"groups":["a","a-copy"],"keys":["KEY"],"origins":["",""],"same_origin":false,"values_match":true,
          "remove_group":"a-copy","remove_command":"jit vault duplicates --prune","prunable":true,"remove_paths":["a-copy/KEY"]}],
         "shared_credentials":[],"secrets_compared":2}
        """#
        let dialog = try JSONDecoder().decode(VaultDuplicates.self, from: Data(json.utf8)).pruneConfirmation()
        XCTAssertEqual(dialog.title, "Prune 1 stale secret?")
        XCTAssertEqual(dialog.arguments, ["vault", "duplicates", "--prune", "--yes"])
        XCTAssertTrue(dialog.message.contains("a-copy/KEY"), dialog.message)
    }
}
