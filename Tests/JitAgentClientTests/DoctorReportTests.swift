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
        let remove = DoctorAdvice.actions(for: rm).first
        XCTAssertEqual(remove?.title, "Remove Secrets")
        XCTAssertTrue(remove?.destructive ?? false)
        XCTAssertEqual(remove?.argv, [["vault", "rm", "k8s", "--yes"]], "runs in the app, y/N pre-answered after the app's own confirm")
        XCTAssertTrue(DoctorAdvice.orphanActions.contains { $0.command == "jit vault orphans --prune" && $0.destructive })
        XCTAssertTrue(DoctorAdvice.generic("sudo rm /usr/local/bin/jit").destructive)
        XCTAssertFalse(DoctorAdvice.generic("jit service restart").destructive)
    }

    func testFilePickingActions() {
        let backup = DoctorAdvice.actions(for: item("backup", action: "`jit vault export <file>` makes a copy")).first
        XCTAssertEqual(backup?.needs, .newFile(placeholder: "<file>"))
        XCTAssertEqual(
            backup?.argv,
            [["vault", "export", "<file>", "--stdin"]],
            "the passphrase rides stdin, the panel's path replaces <file>"
        )
        XCTAssertEqual(backup?.input, .passphrase(prompt: "A passphrase for the backup file"))
        let legacy = DoctorAdvice.actions(for: item("legacy_envelope", action: "`jit vault export <file>` then `jit vault import <file>`"))
            .first
        XCTAssertEqual(
            legacy?.argv,
            [["vault", "export", "<file>", "--stdin"], ["vault", "import", "<file>", "--stdin", "--yes"]],
            "one action, both steps, one passphrase"
        )
        let generic = DoctorAdvice.generic("jit migrate <path>")
        XCTAssertEqual(generic.needs, .existingPath(placeholder: "<path>"))
        XCTAssertEqual(generic.title, "Choose…")
    }

    func testMissingSecretOffersSetAndMigrate() {
        let advice = "`jit vault set mcp/URL`, or `jit migrate <path>` to convert"
        let missing = DoctorItem(
            kind: "missing",
            scope: "global",
            profile: "mcp",
            variable: "URL",
            path: "mcp/URL",
            detail: "",
            action: advice
        )
        let actions = DoctorAdvice.actions(for: missing)
        XCTAssertEqual(actions.map(\.title), ["Set Value", "Migrate a File"])
        XCTAssertEqual(actions[0].argv, [["vault", "set", "mcp/URL", "--stdin", "--yes"]], "typed in the app, fed on stdin")
        XCTAssertEqual(actions[0].input, .secret(prompt: "The value for mcp/URL"))
        XCTAssertNil(actions[1].argv, "a migrate shows its plan, so it stays in the terminal")
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

extension DoctorAdviceTests {
    /// A command the app runs itself must never stop at a y/N or a hidden
    /// prompt: every mutating one carries --yes, and every one that reads
    /// a secret carries --stdin with an input to feed it.
    func testEveryInAppCommandIsPreAnswered() {
        let samples: [DoctorItem] = [
            item("orphan"), item("origin_gone", action: "`jit vault rm g` if gone"), item("rekey"), item("backup"),
            item("vault_key"), item("legacy_envelope"), item("service", action: "`jit service restart` to start it"),
            DoctorItem(kind: "corrupt", scope: nil, profile: "p", variable: "V", path: "p/V", detail: nil, action: nil),
            DoctorItem(kind: "mount_stale", scope: "mount", profile: nil, variable: nil, path: "/x/.env", detail: nil, action: nil)
        ]
        let all = samples.flatMap(DoctorAdvice.actions(for:)) + DoctorAdvice.orphanActions
        XCTAssertGreaterThan(all.filter { $0.argv != nil }.count, 8)
        for action in all {
            for arguments in action.argv ?? [] {
                let mutating = ["rm", "--prune", "import", "rekey", "set", "unmount"].contains { arguments.contains($0) }
                if mutating {
                    XCTAssertTrue(arguments.contains("--yes"), "\(arguments) would stop at a y/N")
                }
                if arguments.contains("--stdin") {
                    XCTAssertNotNil(action.input, "\(arguments) reads stdin but nothing feeds it")
                }
            }
        }
        XCTAssertTrue(DoctorAdvice.orphanActions.contains { $0.showsOutput }, "Inspect shows the list in the app")
    }
}
