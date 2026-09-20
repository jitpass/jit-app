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
    private var sample: VaultOrphans {
        VaultOrphans(
            count: 5,
            orphans: [
                VaultOrphan(path: "aws-prod/SESSION_TOKEN", origin: "no recorded origin (pre-provenance, or set directly)"),
                VaultOrphan(path: "aws-prod/ACCESS_KEY_ID", origin: "no recorded origin (pre-provenance, or set directly)"),
                VaultOrphan(path: "inventory/JAMF_URL", origin: "/Users/me/work/inventory/.env"),
                VaultOrphan(path: "inventory/JAMF_EA_NAME", origin: "/Users/me/work/inventory/.env"),
                VaultOrphan(path: "loose", origin: "/Users/me/other/.env")
            ],
            staleMounts: [VaultStaleMount(mountPath: "/Users/me/gone/.env", profilePath: "/Users/me/gone/.jit/profiles/env.json")]
        )
    }

    /// Captured from `jit vault orphans --format json` on 2026-09-20: jit
    /// fills `origin` with a sentence when it recorded no file, so an
    /// empty check is not enough. It reached the old dialog on every line,
    /// and it must never reach Show Origin in Finder.
    func testJitsNoOriginSentenceIsNotAFile() {
        let sentinel = "no recorded origin (pre-provenance, or set directly)"
        let orphans = VaultOrphans(
            count: 2,
            orphans: [
                VaultOrphan(path: "scratch/API_KEY", origin: sentinel),
                VaultOrphan(path: "scratch/DB_URL", origin: "~/work/scratch/.env")
            ]
        )
        XCTAssertNil(orphans.orphans[0].originFile, "a sentence is not a path")
        XCTAssertEqual(orphans.orphans[1].originFile, "~/work/scratch/.env")
        XCTAssertEqual(orphans.groups[0].origins, ["~/work/scratch/.env"], "only real files are offered as origins")
        XCTAssertTrue(orphans.groups(matching: "pre-provenance").isEmpty, "the sentence is not searchable text either")
        XCTAssertEqual(orphans.groups(matching: "work/scratch").map(\.name), ["scratch"])
    }

    func testGroupsByProjectInPathOrder() {
        let groups = sample.groups
        XCTAssertEqual(groups.map(\.name), ["aws-prod", "inventory", "loose"])
        XCTAssertEqual(groups[0].keys, ["ACCESS_KEY_ID", "SESSION_TOKEN"], "sorted by path inside the project")
        XCTAssertEqual(groups[0].origins, [], "jit recorded none")
        XCTAssertEqual(groups[1].origins, ["/Users/me/work/inventory/.env"], "one origin, named once")
        XCTAssertEqual(groups[2].keys, ["loose"], "a path with no slash is its own project")
        XCTAssertEqual(groups[1].paths, ["inventory/JAMF_EA_NAME", "inventory/JAMF_URL"])
    }

    func testFilterMatchesProjectKeyAndOrigin() {
        XCTAssertEqual(sample.groups(matching: "AWS").map(\.name), ["aws-prod"], "the project, case-insensitively")
        let byKey = sample.groups(matching: "jamf_url")
        XCTAssertEqual(byKey.map(\.name), ["inventory"])
        XCTAssertEqual(byKey[0].keys, ["JAMF_URL"], "only the matching secret survives inside a group that did not match")
        XCTAssertEqual(sample.groups(matching: "work/inventory").map(\.name), ["inventory"], "the origin counts")
        XCTAssertTrue(sample.groups(matching: "nothing").isEmpty)
        XCTAssertEqual(sample.groups(matching: "  ").count, 3, "a blank filter is no filter")
    }

    /// The dialog must say the secrets go, because `--prune` is the only
    /// command that clears a registration and it deletes them in the same
    /// pass. This is the guard against the old all-or-nothing prune coming
    /// back wearing a mount's name.
    func testClearingMountsSaysWhichSecretsGoWithThem() {
        let dialog = sample.staleMountConfirmation(home: "/Users/me")
        XCTAssertEqual(dialog.title, "Clearing 1 stale mount registration also deletes 5 orphaned secrets")
        XCTAssertEqual(dialog.button, "Clear and Delete 5")
        XCTAssertTrue(dialog.breaks, "neither Return nor the default button deletes five secrets")
        XCTAssertEqual(dialog.arguments, ["vault", "orphans", "--prune", "--yes"])
        XCTAssertEqual(dialog.paths.count, 5)
        XCTAssertTrue(dialog.message.contains("~/gone/.env"), dialog.message)
        XCTAssertTrue(dialog.message.contains("no archive and no undo"), dialog.message)
        XCTAssertTrue(dialog.message.hasSuffix("Touch ID follows."), dialog.message)
    }

    func testMountsAloneTouchNoSecretAndAskNoGesture() {
        let orphans = VaultOrphans(staleMounts: [VaultStaleMount(mountPath: "/Users/me/a/.env", profilePath: "")])
        let dialog = orphans.staleMountConfirmation(home: "/Users/me")
        XCTAssertEqual(dialog.title, "Clear 1 stale mount registration?")
        XCTAssertEqual(dialog.button, "Clear")
        XCTAssertFalse(dialog.breaks)
        XCTAssertTrue(dialog.message.contains("no secret is touched"), dialog.message)
        XCTAssertTrue(dialog.message.contains("no Touch ID is asked"), dialog.message)
    }

    func testNothingLeftToClearOffersNoButton() {
        XCTAssertNil(VaultOrphans(orphans: [VaultOrphan(path: "a/B")]).staleMountConfirmation().button)
    }

    /// No dialog in this flow quotes the command it runs: the reader is
    /// deciding about secrets, not about jit's flags.
    func testNoDialogQuotesItsCommand() {
        let mountsOnly = VaultOrphans(staleMounts: [VaultStaleMount(mountPath: "/a", profilePath: "")])
        let messages = [sample.staleMountConfirmation(home: "/Users/me").message, mountsOnly.staleMountConfirmation().message]
        for message in messages {
            XCTAssertFalse(message.contains("This runs"), message)
            XCTAssertFalse(message.contains("jit vault"), message)
        }
    }
}
