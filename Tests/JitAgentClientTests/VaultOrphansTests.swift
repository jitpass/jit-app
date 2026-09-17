// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class VaultOrphansTests: XCTestCase {
    func testDecodesOrphansAndStaleMounts() throws {
        let json = #"""
        {"count":2,"orphans":[{"path":"old/KEY","origin":"~/old/.env"},{"path":"x/Y","origin":""}],
         "stale_mounts":[{"mount_path":"/Users/me/gone/.env","profile_path":"/Users/me/gone/.jit/profiles/env.json"}]}
        """#
        let orphans = try JSONDecoder().decode(VaultOrphans.self, from: Data(json.utf8))
        XCTAssertEqual(orphans.count, 2)
        XCTAssertEqual(orphans.orphans.map(\.path), ["old/KEY", "x/Y"])
        XCTAssertEqual(orphans.orphans[0].origin, "~/old/.env")
        XCTAssertEqual(orphans.staleMounts.map(\.mountPath), ["/Users/me/gone/.env"])
        XCTAssertFalse(orphans.isEmpty)
    }

    func testEmptyReportDecodes() throws {
        let orphans = try JSONDecoder().decode(VaultOrphans.self, from: Data(#"{"count":0,"orphans":[],"stale_mounts":[]}"#.utf8))
        XCTAssertTrue(orphans.isEmpty)
        XCTAssertEqual(orphans.count, 0)
    }
}
