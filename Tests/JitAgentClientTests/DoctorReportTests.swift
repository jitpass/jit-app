// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class DoctorReportTests: XCTestCase {
    private let json = #"""
    {"schema_version":1,"tool":{"version":"1.5.2","build":"98910ac9456f","signature":"signed CZC6BH93GJ"},
     "profiles_checked":24,"secrets_checked":71,"ok":false,
     "problems":[{"kind":"missing","profile":"mcp-caido-2","scope":"global","variable":"CAIDO_URL",
                  "path":"mcp-caido-2/CAIDO_URL","detail":"","action":"`jit vault set mcp-caido-2/CAIDO_URL`, or `jit migrate <path>`"}],
     "warnings":[{"kind":"mount_stale","scope":"mount","path":"/Users/me/x/.env",
                  "detail":"the mount at ~/x/.env is still registered, but its profile is gone",
                  "action":"`jit vault orphans --prune` clears it, or `jit unmount ~/x/.env`"}]}
    """#

    func testDecodesSectionsAndVerdict() throws {
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.tool?.signature, "signed CZC6BH93GJ")
        XCTAssertEqual(r.profilesChecked, 24)
        XCTAssertEqual(r.verdict, "1 problem, 1 warning")
        XCTAssertEqual(r.brokenProfiles, ["mcp-caido-2": "missing: CAIDO_URL"])
    }

    func testItemsSummariseAndNameTheOneCommand() throws {
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        XCTAssertEqual(r.problems[0].summary, "profile \"mcp-caido-2\": CAIDO_URL missing")
        XCTAssertEqual(r.problems[0].command, "jit vault set mcp-caido-2/CAIDO_URL")
        XCTAssertEqual(r.warnings[0].command, "jit vault orphans --prune")
        XCTAssertEqual(r.warnings[0].commands, ["jit vault orphans --prune", "jit unmount ~/x/.env"])
        XCTAssertTrue(r.problems[0].isGlobalProfileProblem)
        XCTAssertFalse(r.warnings[0].isGlobalProfileProblem)
        XCTAssertEqual(r.warnings[0].summary, "the mount at ~/x/.env is still registered, but its profile is gone")
    }

    func testPlaceholderIsFound() {
        XCTAssertEqual(DoctorItem.placeholder(in: "jit vault export <file>"), "<file>")
        XCTAssertEqual(DoctorItem.placeholder(in: "jit migrate <path>"), "<path>")
        XCTAssertNil(DoctorItem.placeholder(in: "jit vault orphans --prune"))
    }

    func testCleanReportReadsAllGood() throws {
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(#"{"ok":true}"#.utf8))
        XCTAssertEqual(r.verdict, "all good")
    }
}

final class DoctorAdviceTests: XCTestCase {
    private func item(_ kind: String, profile: String? = nil, variable: String? = nil, action: String? = nil) -> DoctorItem {
        DoctorItem(kind: kind, scope: nil, profile: profile, variable: variable, path: nil, detail: nil, action: action)
    }

    func testGroupsKeepFirstSeenOrderAndTitleKnownKinds() {
        let groups = DoctorAdvice.groups([item("mount_stale"), item("backup"), item("mount_stale"), item("new_kind")])
        XCTAssertEqual(groups.map(\.kind), ["mount_stale", "backup", "new_kind"])
        XCTAssertEqual(groups[0].title, "Stale mounts")
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(groups[2].title, "New Kind", "an unknown kind still gets a readable title")
    }

    func testStaleMountsUnmountPerRowAndAllAtOnceNeverPrune() {
        let action = "`jit unmount ~/a/.env` clears just this registration; `jit vault orphans --prune` clears every stale mount"
        let first = DoctorItem(
            kind: "mount_stale",
            scope: "mount",
            profile: nil,
            variable: nil,
            path: "/a/.env",
            detail: nil,
            action: action
        )
        let second = DoctorItem(
            kind: "mount_stale",
            scope: "mount",
            profile: nil,
            variable: nil,
            path: "/b/.env",
            detail: nil,
            action: action
        )
        let one = DoctorAdvice.actions(for: first)
        XCTAssertEqual(one.map(\.title), ["Unmount"])
        XCTAssertEqual(one.first?.argv, [["unmount", "--yes", "/a/.env"]], "runs in the app: no secret is touched, so no Touch ID")
        XCTAssertEqual(one.first?.command, "jit unmount /a/.env")
        let group = DoctorAdvice.groups([first, second])[0]
        XCTAssertEqual(group.groupAction?.title, "Unmount All")
        XCTAssertEqual(group.groupAction?.argv, [["unmount", "--yes", "/a/.env"], ["unmount", "--yes", "/b/.env"]])
        XCTAssertNil(DoctorAdvice.groups([first])[0].groupAction, "one mount needs no group button")
    }

    func testDestructiveCommandsAreMarked() {
        let rm = item("origin_gone", action: "nothing, if you still use these: `jit vault rm k8s` if the project is gone")
        XCTAssertEqual(DoctorAdvice.actions(for: rm), [DoctorAction("Remove Secrets", "jit vault rm k8s", destructive: true)])
        XCTAssertTrue(DoctorAdvice.orphanActions.contains { $0.command == "jit vault orphans --prune" && $0.destructive })
        XCTAssertTrue(DoctorAdvice.generic("sudo rm /usr/local/bin/jit").destructive)
        XCTAssertFalse(DoctorAdvice.generic("jit service restart").destructive)
    }

    func testFilePickingActions() {
        let backup = DoctorAdvice.actions(for: item("backup", action: "`jit vault export <file>` makes a copy"))
        XCTAssertEqual(backup, [DoctorAction("Export Backup", "jit vault export <file>", needs: .newFile(placeholder: "<file>"))])
        let legacy = DoctorAdvice.actions(for: item("legacy_envelope", action: "`jit vault export <file>` then `jit vault import <file>`"))
        XCTAssertEqual(legacy.first?.command, "jit vault export <file> && jit vault import <file>", "one action, both steps")
        let generic = DoctorAdvice.generic("jit migrate <path>")
        XCTAssertEqual(generic.needs, .existingPath(placeholder: "<path>"))
        XCTAssertEqual(generic.title, "Choose…")
    }

    func testMissingSecretOffersSetAndMigrate() {
        let missing = item(
            "missing",
            profile: "mcp",
            variable: "URL",
            action: "`jit vault set mcp/URL`, or `jit migrate <path>` to convert"
        )
        XCTAssertEqual(DoctorAdvice.actions(for: missing).map(\.title), ["Set Value", "Migrate a File"])
        XCTAssertEqual(DoctorAdvice.actions(for: missing)[0].command, "jit vault set mcp/URL")
    }

    func testOrphansCountOnceInTheVerdict() throws {
        let json = #"{"ok":true,"problems":[],"warnings":[{"kind":"orphan","path":"a/X"},{"kind":"orphan","path":"a/Y"},"#
            + #"{"kind":"backup"}]}"#
        let report = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.warningCount, 2)
        XCTAssertEqual(report.verdict, "2 warnings")
        XCTAssertEqual(report.warningGroups.map(\.kind), ["orphan", "backup"])
    }
}

extension DoctorAdviceTests {
    func testRowsDoNotRepeatTheGroupNote() {
        let mount = DoctorItem(
            kind: "mount_stale", scope: "mount", profile: nil, variable: nil, path: "/tmp/x/.env",
            detail: "the mount at /tmp/x/.env is still registered, but its profile is gone", action: nil
        )
        XCTAssertEqual(DoctorAdvice.rowText(mount), "/tmp/x/.env")
        XCTAssertTrue(DoctorAdvice.rowIsPath(mount))
        let origin = DoctorItem(
            kind: "origin_gone", scope: nil, profile: nil, variable: nil, path: "~/.kube/config",
            detail: "k8s-docker-desktop was migrated from ~/.kube/config, which no longer exists on disk", action: nil
        )
        XCTAssertEqual(DoctorAdvice.rowText(origin), "k8s-docker-desktop · from ~/.kube/config")
        XCTAssertTrue(DoctorAdvice.rowIsPath(origin))
        let plural = DoctorItem(
            kind: "origin_gone", scope: nil, profile: nil, variable: nil, path: "~/.mcp.json",
            detail: "mcp-a, mcp-b were migrated from ~/.mcp.json, which no longer exists on disk", action: nil
        )
        XCTAssertEqual(DoctorAdvice.rowText(plural), "mcp-a, mcp-b · from ~/.mcp.json")
        let missing = DoctorItem(
            kind: "missing",
            scope: "global",
            profile: "mcp",
            variable: "URL",
            path: "mcp/URL",
            detail: "",
            action: nil
        )
        XCTAssertEqual(DoctorAdvice.rowText(missing), "mcp · URL")
    }
}
