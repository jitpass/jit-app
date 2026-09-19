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

extension VaultOrphansTests {
    func testPruneConfirmationCountsPathsAndStaleMounts() {
        let orphans = VaultOrphans(
            count: 2, orphans: [VaultOrphan(path: "old/KEY", origin: "~/old/.env"), VaultOrphan(path: "x/Y")],
            staleMounts: [VaultStaleMount(mountPath: "/Users/me/gone/.env", profilePath: "/Users/me/gone/.jit/profiles/env.json")]
        )
        let dialog = orphans.pruneConfirmation(home: "/Users/me")
        XCTAssertEqual(dialog.title, "Prune 2 orphaned secrets and clear 1 stale mount?")
        XCTAssertEqual(dialog.button, "Prune")
        XCTAssertEqual(dialog.arguments, ["vault", "orphans", "--prune", "--yes"])
        XCTAssertTrue(dialog.message.contains("old/KEY · from ~/old/.env\nx/Y"), dialog.message)
        XCTAssertTrue(dialog.message.contains("clears 1 stale mount registration"), dialog.message)
        XCTAssertTrue(dialog.message.contains("~/gone/.env"), dialog.message)
        XCTAssertTrue(dialog.message.hasSuffix("Touch ID follows."), dialog.message)
    }

    func testStaleMountsAloneAskNoTouchID() {
        let orphans = VaultOrphans(staleMounts: [VaultStaleMount(mountPath: "/Users/me/a/.env", profilePath: "")])
        let dialog = orphans.pruneConfirmation(home: "/Users/me")
        XCTAssertEqual(dialog.title, "Clear 1 stale mount registration?")
        XCTAssertTrue(dialog.message.contains("no Touch ID is asked"), dialog.message)
    }

    func testFreshEmptyListingOffersNothingAndLongListsAreCapped() {
        XCTAssertNil(VaultOrphans().pruneConfirmation().button)
        let many = VaultOrphans(orphans: (1 ... 20).map { VaultOrphan(path: "g/K\($0)") })
        let dialog = many.pruneConfirmation(home: "/Users/me", limit: 15)
        XCTAssertTrue(dialog.message.contains("…and 5 more"), dialog.message)
        XCTAssertEqual(dialog.paths.count, 20)
    }
}
