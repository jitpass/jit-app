// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Doctor's migrate fixes, run in the app: `jit migrate <file>` (mcp,
/// mcp_nested, jit_path, jit_path_upgrade, a missing secret's Migrate a
/// File) and `jit migrate undo <file>` (an mcp entry whose profile is
/// gone). Each reads jit's own plan from `--dry-run` first, which changes
/// nothing, shows it in the confirmation, and then runs exactly the
/// command the dialog names with --yes. Touch ID is jit's own prompt.
///
/// An older jit's report has no `fixes`, and its commands stay in the
/// terminal as before.
extension DoctorAdvice {
    static func migrateActions(_ item: DoctorItem) -> [DoctorAction] {
        guard let fixes = item.fixes else {
            return item.commands.map { DoctorAction($0.contains("migrate undo") ? "Undo Migration" : "Migrate Again", $0) }
        }
        return fixes.filter { !DoctorItem.needsReference($0.command) }.map { migrateAction($0) ?? generic($0) }
    }

    /// The in-app action for a migrate fix; nil for any other command.
    static func migrateAction(_ fix: DoctorFix) -> DoctorAction? {
        guard !fix.external, fix.argv.first == "migrate", fix.argv.count > 1 else {
            return nil
        }
        if fix.argv[1] == "undo" {
            let targets = Array(fix.argv.dropFirst(2))
            guard !targets.isEmpty else {
                return nil
            }
            return DoctorAction(
                "Undo Migration", fix.command, destructive: true, argv: [["migrate", "undo", "--yes"] + targets], presence: true,
                planned: .undoMigration(targets: targets)
            )
        }
        let targets = Array(fix.argv.dropFirst())
        guard !["remove", "caches", "path"].contains(targets[0]) else {
            return nil
        }
        return DoctorAction(
            "Migrate", fix.command, argv: [["migrate", "--yes"] + targets], presence: true, planned: .migrate(targets: targets)
        )
    }

    /// A missing secret's other fix: migrate the file it came from, which
    /// the user chooses; its plan is read before anything runs.
    static let migrateAFile = DoctorAction(
        "Migrate a File", "jit migrate <path>", needs: .existingPath(placeholder: "<path>"),
        argv: [["migrate", "--yes", "<path>"]], presence: true, planned: .migrate(targets: ["<path>"])
    )
}

/// What `jit migrate <targets> --dry-run` or `jit migrate undo <targets>
/// --dry-run` says it would do: jit's plan as it prints it, without the
/// [DRY RUN] frame, and whether there is anything to do at all.
public struct MigratePlan: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case migrate, undo
    }

    public var mode: Mode
    /// What follows `migrate` or `migrate undo`: files, or `--only <c>`.
    public var targets: [String]
    public var text: String
    public var hasWork: Bool

    public init(mode: Mode, targets: [String], text: String, hasWork: Bool) {
        self.mode = mode
        self.targets = targets
        self.text = text
        self.hasWork = hasWork
    }

    public static func dryRunArguments(_ mode: Mode, _ targets: [String]) -> [String] {
        (mode == .undo ? ["migrate", "undo"] : ["migrate"]) + targets + ["--dry-run"]
    }

    /// What the dialog's button runs.
    public var arguments: [String] {
        (mode == .undo ? ["migrate", "undo", "--yes"] : ["migrate", "--yes"]) + targets
    }

    /// jit's dry-run output as the dialog shows it: colour codes, the two
    /// [DRY RUN] lines and the scan hint after the second one dropped.
    public static func parse(_ output: String, mode: Mode, targets: [String]) -> MigratePlan {
        var lines: [String] = []
        for line in stripANSI(output).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[DRY RUN] Apply") {
                break
            }
            if !trimmed.hasPrefix("[DRY RUN]") {
                lines.append(line)
            }
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWork = switch mode {
        case .migrate: !text.isEmpty && !text.hasPrefix("Nothing to migrate")
        case .undo: text.contains("Restoring ")
        }
        return MigratePlan(mode: mode, targets: targets, text: text, hasWork: hasWork)
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }

    /// The dialog: what it does in plain words, with jit's own plan under
    /// it. An undo writes plaintext back, so its button is the red one that
    /// Return does not press.
    public func confirmation(home: String = NSHomeDirectory()) -> DeleteConfirmation {
        let shown = targets.map { VaultRmPlan.short($0, home) }
        let name = targets.count == 1 && targets[0].hasPrefix("/") ? DoctorAdvice.configShortName(targets[0], home: home)
            : shown.joined(separator: " ")
        guard hasWork else {
            let first = text.components(separatedBy: "\n").first ?? ""
            return DeleteConfirmation(
                title: mode == .undo ? "Nothing to undo" : "Nothing to migrate",
                message: (first.isEmpty ? "jit found nothing to do for \(shown.joined(separator: " "))." : first)
                    + " Nothing was changed.",
                button: nil, breaks: false, arguments: [], destructive: mode == .undo
            )
        }
        let planNote = "jit's plan, from a dry run that changed nothing:"
        if mode == .undo {
            let what = text.contains("Restoring 1 file") && shown.count == 1 ? "the original \(shown[0])" : "the original files"
            return DeleteConfirmation(
                title: "Undo the migration of \(name)?",
                message: "This puts \(what) back on disk, and jit writes real secret values back to disk in plaintext. "
                    + "The vault keeps its copies and the profiles stay. Edits made since the migration are replaced; "
                    + "jit keeps a copy of them in the vault first.\n\nTouch ID follows.\n\n\(planNote)",
                button: "Undo Migration", breaks: true, arguments: arguments, destructive: true
            )
        }
        return DeleteConfirmation(
            title: "Migrate \(name)?",
            message: "jit rewrites what the plan below lists. Every file is backed up, encrypted, before it is touched; "
                + "jit migrate undo restores it.\n\nTouch ID follows if jit needs the vault.\n\n\(planNote)",
            button: "Migrate", breaks: false, arguments: arguments, destructive: false
        )
    }
}

public extension MigratePlan {
    /// When the dry run failed: an undo with no backup on record, a file
    /// jit can't read, a jit too old to answer. Nothing runs.
    static func unavailable(_ mode: Mode, targets: [String], reason: String, home: String = NSHomeDirectory()) -> DeleteConfirmation {
        let command = "jit " + (mode == .undo ? "migrate undo " : "migrate ") + targets.map { VaultRmPlan.short($0, home) }
            .joined(separator: " ")
        return DeleteConfirmation(
            title: mode == .undo ? "Can't check what undoing would restore" : "Can't check what migrating would change",
            message: "Nothing was changed. Before it runs \(command), JitPass asks jit what it would do, and jit did not answer:\n\n"
                + (reason.isEmpty ? "(no output)" : reason),
            button: nil, breaks: false, arguments: []
        )
    }
}
