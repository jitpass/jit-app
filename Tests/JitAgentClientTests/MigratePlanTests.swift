// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Doctor's migrate and undo fixes run in the app: jit's dry run is read
/// first and shown, and the dialog's button runs exactly the command it
/// names.
final class MigratePlanTests: XCTestCase {
    private let config = "/Users/me/Security-Ops/.mcp.json"

    /// `jit migrate undo ~/Security-Ops/.mcp.json --dry-run` from jit 2.0.0,
    /// home renamed; the colour codes a terminal would get added back.
    private let undoOutput = """
    \u{1B}[1m[DRY RUN] Preview, this run changes nothing; the plan below is what a real run would do.\u{1B}[0m

    Restoring 1 file from encrypted backups:
      • ~/Security-Ops/.mcp.json (backed up 2m ago)

    Each file is restored EXACTLY as backed up, edits made since are replaced
    (the replaced content is snapshotted into the vault first, so this is itself
    undoable), and real secret values return to disk in PLAINTEXT.
    Vault secrets and profile manifests are left in place, this reverses files, never the vault.

    [DRY RUN] Apply this plan: jit migrate undo /Users/me/Security-Ops/.mcp.json
    """

    /// A migrate plan's shape (jitpass/jit internal/cli/migrate.go): the
    /// frame, the plan, the trailer and its scan hint.
    private let migrateOutput = """
    [DRY RUN] Preview, this run changes nothing; the plan below is what a real run would do.

    [mcp] 1
      ~/Security-Ops/.mcp.json
        note: collapsed 2 nested wrappers into one

    [DRY RUN] Apply this plan: `jit migrate /Users/me/Security-Ops/.mcp.json`
    This only covers what jit migrate can act on; run `jit scan` for the complete picture,
    including findings it can never auto-fix, like private keys.
    """

    func testDoctorsMigrateFixesRunInTheApp() {
        let nested = DoctorItem(
            kind: "mcp_nested", profile: "mcp-caido", path: config, detail: "\"caido\" in ~/Security-Ops/.mcp.json runs jit inside jit",
            fixes: [DoctorFix(command: "jit migrate ~/Security-Ops/.mcp.json", argv: ["migrate", config], destructive: false)]
        )
        let migrate = DoctorAdvice.actions(for: nested)
        XCTAssertEqual(migrate.map(\.title), ["Migrate"])
        XCTAssertEqual(migrate.first?.planned, .migrate(targets: [config]))
        XCTAssertEqual(migrate.first?.argv, [["migrate", "--yes", config]])
        XCTAssertEqual(migrate.first?.destructive, false)
        XCTAssertEqual(migrate.first?.buttonTitle, "Migrate…")

        let gone = DoctorItem(
            kind: "mcp", profile: "mcp-x", path: config,
            fixes: [DoctorFix(
                command: "jit migrate undo ~/Security-Ops/.mcp.json", argv: ["migrate", "undo", config], destructive: true, presence: true
            )]
        )
        let undo = DoctorAdvice.actions(for: gone)
        XCTAssertEqual(undo.map(\.title), ["Undo Migration"])
        XCTAssertEqual(undo.first?.planned, .undoMigration(targets: [config]))
        XCTAssertEqual(undo.first?.argv, [["migrate", "undo", "--yes", config]])
        XCTAssertEqual(undo.first?.destructive, true)
        XCTAssertEqual(undo.first?.presence, true)

        let byCategory = DoctorItem(
            kind: "jit_path_upgrade", path: "/Users/me/.aws/config",
            fixes: [DoctorFix(command: "jit migrate --only aws", argv: ["migrate", "--only", "aws"], destructive: false)]
        )
        XCTAssertEqual(DoctorAdvice.actions(for: byCategory).first?.planned, .migrate(targets: ["--only", "aws"]))
    }

    /// A report from before `fixes` keeps the terminal, as it always did.
    func testAnOlderReportStaysInTheTerminal() {
        let old = DoctorItem(kind: "mcp_nested", path: config, action: "`jit migrate ~/Security-Ops/.mcp.json` to collapse each")
        let actions = DoctorAdvice.actions(for: old)
        XCTAssertEqual(actions.map(\.title), ["Migrate Again"])
        XCTAssertNil(actions.first?.argv)
        XCTAssertNil(actions.first?.planned)
    }

    func testParseDropsTheDryRunFrame() {
        let plan = MigratePlan.parse(migrateOutput, mode: .migrate, targets: [config])
        XCTAssertTrue(plan.hasWork)
        XCTAssertEqual(plan.text, "[mcp] 1\n  ~/Security-Ops/.mcp.json\n    note: collapsed 2 nested wrappers into one")
        XCTAssertEqual(MigratePlan.dryRunArguments(.migrate, [config]), ["migrate", config, "--dry-run"])
        XCTAssertEqual(MigratePlan.dryRunArguments(.undo, [config]), ["migrate", "undo", config, "--dry-run"])
        XCTAssertEqual(plan.arguments, ["migrate", "--yes", config])

        let undo = MigratePlan.parse(undoOutput, mode: .undo, targets: [config])
        XCTAssertTrue(undo.hasWork)
        XCTAssertTrue(undo.text.hasPrefix("Restoring 1 file from encrypted backups:"))
        XCTAssertFalse(undo.text.contains("DRY RUN"))
        XCTAssertFalse(undo.text.contains("\u{1B}"))
        XCTAssertEqual(undo.arguments, ["migrate", "undo", "--yes", config])
    }

    func testMigrateConfirmation() {
        let dialog = MigratePlan.parse(migrateOutput, mode: .migrate, targets: [config]).confirmation(home: "/Users/me")
        XCTAssertEqual(dialog.title, "Migrate Security-Ops/.mcp.json?")
        XCTAssertEqual(dialog.message, """
        jit rewrites what the plan below lists. Every file is backed up, encrypted, before it is touched; \
        jit migrate undo restores it.

        This runs:

        jit migrate --yes ~/Security-Ops/.mcp.json

        Nothing asks again. Touch ID follows if jit needs the vault.

        jit's plan, from a dry run that changed nothing:
        """)
        XCTAssertEqual(dialog.button, "Migrate")
        XCTAssertFalse(dialog.breaks)
        XCTAssertFalse(dialog.destructive)
        XCTAssertEqual(dialog.arguments, ["migrate", "--yes", config])
    }

    /// Undo puts plaintext back: the dialog says so in jit's words, and the
    /// button is the red one Return does not press.
    func testUndoConfirmation() {
        let dialog = MigratePlan.parse(undoOutput, mode: .undo, targets: [config]).confirmation(home: "/Users/me")
        XCTAssertEqual(dialog.title, "Undo the migration of Security-Ops/.mcp.json?")
        XCTAssertEqual(dialog.message, """
        This puts the original ~/Security-Ops/.mcp.json back on disk, and jit writes real secret values back to disk \
        in plaintext. The vault keeps its copies and the profiles stay. Edits made since the migration are replaced; \
        jit keeps a copy of them in the vault first.

        This runs:

        jit migrate undo --yes ~/Security-Ops/.mcp.json

        Nothing asks again. Touch ID follows.

        jit's plan, from a dry run that changed nothing:
        """)
        XCTAssertEqual(dialog.button, "Undo Migration")
        XCTAssertTrue(dialog.breaks, "red, and not the Return default")
        XCTAssertTrue(dialog.destructive)
        XCTAssertEqual(dialog.arguments, ["migrate", "undo", "--yes", config])
    }

    func testNothingToDoRunsNothing() {
        let none = MigratePlan.parse(
            "Nothing to migrate: none of the path(s) you named contain plaintext secrets jit can move.\n", mode: .migrate, targets: [config]
        )
        XCTAssertFalse(none.hasWork)
        let dialog = none.confirmation(home: "/Users/me")
        XCTAssertEqual(dialog.title, "Nothing to migrate")
        XCTAssertNil(dialog.button)
        XCTAssertEqual(dialog.arguments, [])
        XCTAssertEqual(
            dialog.message, "Nothing to migrate: none of the path(s) you named contain plaintext secrets jit can move. Nothing was changed."
        )
        let unavailable = MigratePlan.unavailable(.undo, targets: [config], reason: "no recorded backup for it", home: "/Users/me")
        XCTAssertEqual(unavailable.title, "Can't check what undoing would restore")
        XCTAssertNil(unavailable.button)
        XCTAssertTrue(unavailable.message.hasPrefix("Nothing was changed. Before it runs jit migrate undo ~/Security-Ops/.mcp.json,"))
    }
}
