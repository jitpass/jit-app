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
