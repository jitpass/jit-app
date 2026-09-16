// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class DoctorReportTests: XCTestCase {
    func testBrokenProfilesNameTheMissingVariable() throws {
        let json = #"""
        {"ok":false,"profiles_checked":24,"problems":[
          {"kind":"missing","profile":"mcp-caido-2","scope":"global","variable":"CAIDO_URL","path":"mcp-caido-2/CAIDO_URL",
           "detail":"","action":"`jit vault set mcp-caido-2/CAIDO_URL`"}]}
        """#
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.brokenProfiles, ["mcp-caido-2": "missing: CAIDO_URL"])
    }
}
