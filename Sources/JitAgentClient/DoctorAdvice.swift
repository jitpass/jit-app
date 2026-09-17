// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A button on a doctor row: a verb, the command it runs, and what it
/// needs before it can run. The command always runs in the terminal, so
/// jit's own confirmations and Touch ID still apply; `destructive` only
/// changes how the button looks and adds the app's own confirmation.
public struct DoctorAction: Equatable, Sendable {
    public enum Needs: Equatable, Sendable {
        /// Runs as written.
        case nothing
        /// An existing file or folder replaces `<placeholder>`.
        case existingPath(placeholder: String)
        /// A file to create replaces `<placeholder>`; every occurrence.
        case newFile(placeholder: String)
    }

    public var title: String
    public var command: String
    public var destructive: Bool
    public var needs: Needs
    /// When set, the app runs these jit invocations itself, one after the
    /// other, and rechecks; no terminal. Only for a command that needs no
    /// Touch ID and no answer from the user, with any y/N pre-answered.
    /// `command` stays what a hover shows.
    public var argv: [[String]]?

    public init(_ title: String, _ command: String, destructive: Bool = false, needs: Needs = .nothing, argv: [[String]]? = nil) {
        self.title = title
        self.command = command
        self.destructive = destructive
        self.needs = needs
        self.argv = argv
    }
}

/// Findings of one kind, with the title and note the window shows for
/// that kind and, when the rows share a fix, one action for the lot.
public struct DoctorGroup: Equatable, Sendable, Identifiable {
    public var kind: String
    public var title: String
    public var note: String?
    public var items: [DoctorItem]
    /// A group-level action (unmount all), present when it saves clicks.
    public var groupAction: DoctorAction?

    public var id: String {
        kind
    }
}

public enum DoctorAdvice {
    /// Kinds whose many rows are one thing to a reader: shown as a count,
    /// listed on demand.
    public static let listedKinds: Set<String> = ["orphan"]

    static let titles: [String: (title: String, note: String?)] = [
        "missing": (
            "Missing secrets",
            "A profile points at a secret the vault does not hold; a tool launched through it gets an empty value."
        ),
        "corrupt": ("Unreadable secrets", "The stored value is not in a format this jit can decrypt."),
        "parse": ("Profiles that won't load", nil),
        "not_found": ("Profile not found", nil),
        "vault_error": ("Vault errors", nil),
        "bad_path": ("Bad secret paths", nil),
        "vault_key": ("Master key missing", "Without this Mac's master key nothing in the vault decrypts."),
        "rekey": ("Unfinished key rotation", "Every vault write is refused until the rotation completes."),
        "wrap": ("Broken wrapped tools", "The tool now runs unwrapped, or not at all."),
        "mcp": ("Broken MCP entries", nil),
        "jit_path": ("Stale jit paths", "A credential helper points at a jit binary that is gone."),
        "1password": ("1Password CLI", nil),
        "1password_link": ("Broken 1Password links", nil),
        "orphan": ("Orphaned secrets", "In the vault but referenced by no profile jit can see. Harmless, but dead weight."),
        "duplicates": ("Possible duplicates", "Vault groups that look like the same file stored twice."),
        "origin_gone": (
            "Origin files gone",
            "The file these were migrated from no longer exists. Nothing to do if you still use them: the vault is where they live now."
        ),
        "shadowed": ("Shadowed profiles", "A project profile with the same name wins; the global copy is ignored there."),
        "service": ("Background service", nil),
        "backup": ("Backup", nil),
        "mount": ("Mounts", nil),
        "mount_stale": (
            "Stale mounts",
            "Registered mounts whose project was deleted without unmounting first. Unmounting touches no secret."
        ),
        "wrap_env": ("Wrapped tools, this shell only", "Only true of the shell the check ran in."),
        "audit": ("Audit log", nil),
        "install": ("Extra jit installs", "PATH order decides which copy runs."),
        "jit_path_upgrade": ("Version-pinned jit paths", "Still working, but the path will break on the next Homebrew upgrade."),
        "completion": ("Shell completion", nil),
        "legacy_envelope": ("Old secret format", nil)
    ]

    /// Problems then warnings, each grouped by kind in first-seen order.
    public static func groups(_ items: [DoctorItem]) -> [DoctorGroup] {
        var order: [String] = []
        var byKind: [String: [DoctorItem]] = [:]
        for item in items {
            if byKind[item.kind] == nil {
                order.append(item.kind)
            }
            byKind[item.kind, default: []].append(item)
        }
        return order.map { kind in
            let members = byKind[kind] ?? []
            let named = titles[kind]
            return DoctorGroup(
                kind: kind,
                title: named?.title ?? kind.replacingOccurrences(of: "_", with: " ").capitalized,
                note: named?.note,
                items: members,
                groupAction: groupAction(kind, members)
            )
        }
    }

    /// The buttons for one row: a verb per command doctor named, from the
    /// table below for the kinds the app knows, and a generic Run or
    /// Choose… for the rest, so a new kind still has its command.
    public static func actions(for item: DoctorItem) -> [DoctorAction] {
        guard let build = builders[item.kind] else {
            return item.commands.map(generic)
        }
        return build(item).filter { !$0.command.isEmpty }
    }

    private typealias Builder = (DoctorItem) -> [DoctorAction]

    private static let builders: [String: Builder] = [
        "missing": { item in [
            DoctorAction("Set Value", first(item.commands, "jit vault set")),
            DoctorAction("Migrate a File", "jit migrate <path>", needs: .existingPath(placeholder: "<path>"))
        ] },
        "corrupt": { item in [
            DoctorAction("Show History", first(item.commands, "jit vault history")),
            DoctorAction("Replace Value", first(item.commands, "jit vault set"), destructive: true)
        ] },
        "orphan": { item in item.path == nil ? orphanActions : [] },
        "duplicates": { _ in [DoctorAction("Compare", "jit vault duplicates")] },
        "origin_gone": { item in [DoctorAction("Remove Secrets", first(item.commands, "jit vault rm"), destructive: true)] },
        "service": { item in item.commands.map {
            $0.hasPrefix("jit service log")
                ? DoctorAction("Show Log", $0)
                : DoctorAction("Restart Service", $0, argv: [["service", "restart"]])
        } },
        "backup": { _ in [DoctorAction("Export Backup", "jit vault export <file>", needs: .newFile(placeholder: "<file>"))] },
        "mount": unmount,
        "mount_stale": { item in
            // Clearing a stale registration decrypts nothing and writes
            // nothing, so the CLI asks only y/N; the app answers it.
            guard let path = item.path else {
                return unmount(item)
            }
            return [DoctorAction("Unmount", "jit unmount \(homePath(path))", argv: [["unmount", "--yes", path]])]
        },
        "vault_key": { _ in
            [DoctorAction("Import a Backup", "jit vault import <file>", needs: .existingPath(placeholder: "<file>"))]
        },
        "rekey": { _ in [DoctorAction("Finish Rotation", "jit vault rekey")] },
        "legacy_envelope": { _ in
            let both = "jit vault export <file> && jit vault import <file>"
            return [DoctorAction("Re-encrypt", both, needs: .newFile(placeholder: "<file>"))]
        },
        "mcp": migrate,
        "jit_path": migrate,
        "jit_path_upgrade": migrate,
        "install": { item in item.commands.map {
            DoctorAction($0.hasPrefix("brew uninstall") ? "Uninstall Homebrew Copy" : "Remove", $0, destructive: true)
        } },
        "completion": { item in item.commands.map { DoctorAction("Install Completion", $0) } },
        "1password": { item in item.commands.map { DoctorAction("Install op CLI", $0) } }
    ]

    private static let unmount: Builder = { item in
        item.commands.filter { $0.hasPrefix("jit unmount") }
            .map { DoctorAction($0.hasSuffix("--all") ? "Unmount All" : "Unmount", $0) }
    }

    private static let migrate: Builder = { item in
        item.commands.map { DoctorAction($0.contains("migrate undo") ? "Undo Migration" : "Migrate Again", $0) }
    }

    public static let orphanActions = [
        DoctorAction("Inspect", "jit vault orphans"),
        DoctorAction("Delete All", "jit vault orphans --prune", destructive: true)
    ]

    /// One action for the whole group: every stale mount unmounted in one
    /// terminal run, one line per mount.
    static func groupAction(_ kind: String, _ items: [DoctorItem]) -> DoctorAction? {
        guard kind == "mount_stale", items.count > 1 else {
            return nil
        }
        let paths = items.compactMap(\.path)
        guard paths.count > 1 else {
            return nil
        }
        let shown = paths.map { "jit unmount \(homePath($0))" }.joined(separator: "\n")
        return DoctorAction("Unmount All", shown, argv: paths.map { ["unmount", "--yes", $0] })
    }

    /// A command the app has no verb for: Run, or Choose… when it names a
    /// `<file>`/`<path>` the user must supply. Destructive when it is one
    /// of the commands known to delete.
    static func generic(_ command: String) -> DoctorAction {
        let destructive = command.hasPrefix("sudo rm") || command.hasPrefix("jit vault rm")
            || command.hasSuffix("--prune")
        if let placeholder = DoctorItem.placeholder(in: command) {
            let needs: DoctorAction.Needs = command.hasPrefix("jit vault export")
                ? .newFile(placeholder: placeholder) : .existingPath(placeholder: placeholder)
            return DoctorAction("Choose…", command, destructive: destructive, needs: needs)
        }
        return DoctorAction("Run", command, destructive: destructive)
    }

    static func first(_ commands: [String], _ prefix: String) -> String {
        commands.first { $0.hasPrefix(prefix) } ?? ""
    }
}

public extension DoctorAdvice {
    /// What the row says. The group title and note already say what the
    /// kind means, so a row repeats none of it: a mount row is its path, an
    /// origin row is the secrets and the file they came from, a profile
    /// row is the profile and the variable. Anything else is doctor's own
    /// sentence.
    static func rowText(_ item: DoctorItem) -> String {
        switch item.kind {
        case "mount", "mount_stale", "install", "completion", "jit_path", "jit_path_upgrade", "1password_link":
            return item.path.map(homePath) ?? item.summary
        case "origin_gone":
            let detail = item.detail ?? ""
            let verb = detail.range(of: " was migrated from ") ?? detail.range(of: " were migrated from ")
            if let verb, let end = detail.range(of: ", which no longer exists") {
                return "\(detail[..<verb.lowerBound]) · from \(detail[verb.upperBound ..< end.lowerBound])"
            }
            return item.summary
        default:
            if let profile = item.profile, let variable = item.variable, item.detail?.isEmpty ?? true {
                return "\(profile) · \(variable)"
            }
            return item.summary
        }
    }

    /// Rows that are a path read best in monospace, truncated at the start.
    static func rowIsPath(_ item: DoctorItem) -> Bool {
        switch item.kind {
        case "mount", "mount_stale", "install", "completion", "jit_path", "jit_path_upgrade", "1password_link":
            item.path != nil
        case "origin_gone", "missing", "corrupt", "bad_path":
            true
        default:
            false
        }
    }

    static func homePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

public extension DoctorReport {
    var problemGroups: [DoctorGroup] {
        DoctorAdvice.groups(problems)
    }

    var warningGroups: [DoctorGroup] {
        DoctorAdvice.groups(warnings)
    }

    /// Warnings as a reader counts them: a listed kind (every orphaned
    /// secret its own record under --orphans) counts once, matching what
    /// `jit doctor` says without the flag.
    var warningCount: Int {
        var count = 0
        var seen: Set<String> = []
        for warning in warnings {
            if DoctorAdvice.listedKinds.contains(warning.kind) {
                if seen.insert(warning.kind).inserted {
                    count += 1
                }
            } else {
                count += 1
            }
        }
        return count
    }
}
