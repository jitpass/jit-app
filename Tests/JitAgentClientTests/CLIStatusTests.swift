// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class CLIStatusTests: XCTestCase {
    func testDecodesTheSectionsThePanelShows() throws {
        let json = #"""
        {"cli":{"version":"1.5.2"},"vault":{"secrets_stored":114,"backups_stored":170},
         "agent":{"running":true},"mounts":{"registered":15,"being_served":true,"serving_real":false},
         "sessions":[]}
        """#
        let s = try JSONDecoder().decode(CLIStatus.self, from: Data(json.utf8))
        XCTAssertEqual(s.vault?.secretsStored, 114)
        XCTAssertEqual(s.mounts?.registered, 15)
        XCTAssertEqual(s.mounts?.servingReal, false)
    }

    func testMissingSectionsReadAsNil() throws {
        let s = try JSONDecoder().decode(CLIStatus.self, from: Data(#"{"cli":{}}"#.utf8))
        XCTAssertNil(s.vault)
        XCTAssertNil(s.mounts)
    }
}
