// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A button on a doctor row: a verb, the command it runs, and what it
/// needs before it can run. With `argv` the app runs it itself, every y/N
/// pre-answered, so the app's own confirmation is the only question;
/// without, it runs in the terminal, where jit's own y/N and Touch ID
/// apply. `destructive` colours the button red and adds the app's
/// confirmation, worded by `confirmation(for:)`.
public struct DoctorAction: Equatable, Sendable {
    public enum Needs: Equatable, Sendable {
        /// Runs as written.
        case nothing
        /// An existing file or folder replaces `<placeholder>`.
        case existingPath(placeholder: String)
        /// A file to create replaces `<placeholder>`; every occurrence.
        case newFile(placeholder: String)
    }

    /// What the app asks the user for and feeds the command on stdin.
    public enum Input: Equatable, Sendable {
        /// One hidden value, for `jit vault set --stdin`.
        case secret(prompt: String)
        /// A passphrase typed twice, for an export or an import.
        case passphrase(prompt: String)
    }

    /// An action whose confirmation is worded from the engine's own dry
    /// run, fetched the moment it is clicked, and whose command is the one
    /// that confirmation returns: `argv` is then only what the button would
    /// run if the dry run changed nothing.
    public enum Planned: Equatable, Sendable {
        /// `jit profile adopt <config>`.
        case adopt(config: String)
        /// `jit profile rm <profile>`.
        case removeProfile(name: String)
    }

    public var title: String
    /// What a hover shows, and what runs when `argv` is nil.
    public var command: String
    public var destructive: Bool
    public var needs: Needs
    /// When set, the app runs these jit invocations itself, one after the
    /// other, and rechecks: no terminal. Every y/N is pre-answered with
    /// --yes and every hidden prompt replaced by `input` on stdin, so the
    /// command never stops to ask; Touch ID, when jit wants it, is jit's
    /// own prompt and works from the app. A `<file>`/`<path>` token in an
    /// argument is replaced by the path `needs` chose.
    public var argv: [[String]]?
    public var input: Input?
    /// The command's output is what the user wanted (a history, a log, a
    /// list), so the app shows it instead of only rechecking.
    public var showsOutput: Bool
    /// jit asks for a fresh Touch ID or passcode itself, per the engine's
    /// `fixes` (false when the report predates them).
    public var presence: Bool
    public var planned: Planned?

    public init(
        _ title: String, _ command: String, destructive: Bool = false, needs: Needs = .nothing,
        argv: [[String]]? = nil, input: Input? = nil, showsOutput: Bool = false, presence: Bool = false,
        planned: Planned? = nil
    ) {
        self.title = title
        self.command = command
        self.destructive = destructive
        self.needs = needs
        self.argv = argv
        self.input = input
        self.showsOutput = showsOutput
        self.presence = presence
        self.planned = planned
    }
}

/// Findings of one kind, with the title and note the window shows for
/// that kind and, when the rows share a fix, one action for the lot.
public struct DoctorGroup: Equatable, Sendable, Identifiable {
    public var kind: String
    public var title: String
    public var note: String?
    public var items: [DoctorItem]
    /// Group-level actions: Unmount All, when it saves clicks; one Adopt
    /// per MCP config that launches an ownerless profile.
    public var groupActions: [DoctorAction]

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
            "A profile points at a secret the vault does not hold; a tool launched through it won't start."
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
        "mcp_nested": (
            "Doubly wrapped MCP entries",
            "Still working, but the server launches through jit twice. Migrating again collapses it to one."
        ),
        "jit_path": ("Stale jit paths", "A credential helper points at a jit binary that is gone."),
        "1password": ("1Password CLI", nil),
        "1password_link": (
            "Broken 1Password links",
            "The 1Password item a secret links to does not resolve. Fix the item in 1Password, "
                + "or relink it in the terminal with jit vault link <path> <op://…>."
        ),
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
        "install": (
            "Extra jit installs",
            "PATH order decides which copy runs. The Homebrew copy is this app's: brew uninstall jitpass removes JitPass too."
        ),
        "jit_path_upgrade": ("Version-pinned jit paths", "Still working, but the path will break on the next Homebrew upgrade."),
        "completion": ("Shell completion", nil),
        "legacy_envelope": ("Old secret format", nil)
    ].merging(ownershipTitles) { known, _ in known }

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
                note: [named?.note, sharedFacts(kind, members)].compactMap { $0 }.joined(separator: "\n").nilIfEmpty,
                items: members,
                groupActions: groupActions(kind, members)
            )
        }
    }

    /// The buttons for one row: a verb per command doctor named, from the
    /// table below for the kinds the app knows, and a generic Run or
    /// Choose… for the rest, so a new kind still has its command. Never a
    /// command the user has to finish writing (`<op://…>`), and never one
    /// that uninstalls this app.
    ///
    /// With the engine's `fixes` (jit 1.9+), a generic button takes its
    /// destructive, Touch ID and placeholder from the fix, and a kind's own
    /// button keeps its title but turns destructive when a fix it runs is.
    public static func actions(for item: DoctorItem) -> [DoctorAction] {
        let built: [DoctorAction] = if let builder = builders[item.kind] {
            builder(item)
        } else if let fixes = item.fixes {
            fixes.filter { !DoctorItem.needsReference($0.command) }.map(generic)
        } else {
            item.commands.filter { !DoctorItem.needsReference($0) }.map(generic)
        }
        return built.filter { !$0.command.isEmpty && !uninstallsApp($0.command) }
            .map { reconciled($0, with: item.fixes) }
    }

    typealias Builder = (DoctorItem) -> [DoctorAction]

    private static let builders: [String: Builder] = [
        "missing": { item in [
            setValue("Set Value", item),
            DoctorAction("Migrate a File", "jit migrate <path>", needs: .existingPath(placeholder: "<path>"))
        ] },
        "corrupt": { item in [
            show("Show History", ["vault", "history", item.path ?? ""]),
            setValue("Replace Value", item, destructive: true)
        ] },
        "orphan": { item in item.path == nil ? orphanActions : [] },
        "duplicates": { _ in [show("Compare", ["vault", "duplicates"])] },
        // Doctor's advice here is two-sided ("nothing, if you still use
        // these; `jit vault rm` if the project is gone") and only the user
        // knows which side they are on: a one-click delete broke two live
        // MCP profiles whose origin file had merely moved. The row informs;
        // deleting is the Vault window's job, with its own confirmation.
        "origin_gone": { _ in [] },
        "service": { item in item.commands.map {
            $0.hasPrefix("jit service log")
                ? show("Show Log", ["service", "log"])
                : DoctorAction("Restart Service", $0, argv: [["service", "restart"]])
        } },
        "backup": { _ in [DoctorAction(
            "Export Backup", "jit vault export <file>", needs: .newFile(placeholder: "<file>"),
            argv: [["vault", "export", "<file>", "--stdin"]], input: .passphrase(prompt: "A passphrase for the backup file")
        )] },
        "mount": unmount,
        "mount_stale": { item in
            // In the terminal, never with --yes: a stale registration only
            // asks y/N, but if the manifest has reappeared by the time it
            // runs, the same --yes would also answer unmount's "write the
            // secrets back in PLAINTEXT?" unseen.
            guard let path = item.path else {
                return unmount(item)
            }
            return [DoctorAction("Unmount", unmountCommand(path))]
        },
        "vault_key": { _ in [DoctorAction(
            "Import a Backup", "jit vault import <file>", needs: .existingPath(placeholder: "<file>"),
            argv: [["vault", "import", "<file>", "--stdin", "--yes"]], input: .passphrase(prompt: "The backup file's passphrase")
        )] },
        "rekey": { _ in [DoctorAction("Finish Rotation", "jit vault rekey", argv: [["vault", "rekey", "--yes"]])] },
        "legacy_envelope": { _ in [DoctorAction(
            "Re-encrypt", "jit vault export <file> && jit vault import <file>", needs: .newFile(placeholder: "<file>"),
            argv: [["vault", "export", "<file>", "--stdin"], ["vault", "import", "<file>", "--stdin", "--yes"]],
            input: .passphrase(prompt: "A passphrase for the backup file the re-encryption goes through")
        )] },
        "mcp": migrate,
        "mcp_nested": migrate,
        "jit_path": migrate,
        "jit_path_upgrade": migrate,
        // `brew uninstall jitpass` is never offered (actions(for:) drops it):
        // the cask is this app. `sudo rm` is titled with what it deletes,
        // which in the Homebrew case is not the row's path but the copy
        // shells run now.
        "install": { item in item.commands.map { command in
            let removed = command.hasPrefix("sudo rm ") ? String(command.dropFirst("sudo rm ".count)) : ""
            return removed.isEmpty ? generic(command) : DoctorAction("Remove \(homePath(removed))", command, destructive: true)
        } },
        // `jit vault link <path> <op://…>` needs a reference only the user
        // can write; the group note says how.
        "1password_link": { _ in [] },
        "completion": { item in item.commands.map { DoctorAction("Install Completion", $0) } },
        "1password": { item in item.commands.map { DoctorAction("Install op CLI", $0) } }
    ].merging(ownershipBuilders) { known, _ in known }

    private static let unmount: Builder = { item in
        item.commands.filter { $0.hasPrefix("jit unmount") }
            .map { DoctorAction($0.hasSuffix("--all") ? "Unmount All" : "Unmount", $0) }
    }

    private static let migrate: Builder = { item in
        item.commands.map { DoctorAction($0.contains("migrate undo") ? "Undo Migration" : "Migrate Again", $0) }
    }

    /// `jit vault set <path>` with the value typed into the app, hidden,
    /// and fed on stdin. --yes because a corrupt value is being replaced
    /// on purpose; the previous version stays in the vault's history.
    static func setValue(_ title: String, _ item: DoctorItem, destructive: Bool = false) -> DoctorAction {
        guard let path = item.path else {
            return DoctorAction(title, "")
        }
        return DoctorAction(
            title, "jit vault set \(path)", destructive: destructive,
            argv: [["vault", "set", path, "--stdin", "--yes"]], input: .secret(prompt: "The value for \(path)")
        )
    }

    /// A read-only command whose output is the point.
    private static func show(_ title: String, _ arguments: [String]) -> DoctorAction {
        DoctorAction(title, "jit " + arguments.joined(separator: " "), argv: [arguments], showsOutput: true)
    }

    public static let orphanActions = [
        show("Inspect", ["vault", "orphans"]),
        DoctorAction("Delete All", "jit vault orphans --prune", destructive: true, argv: [["vault", "orphans", "--prune", "--yes"]])
    ]

    /// Actions for the whole group: every stale mount unmounted in one
    /// terminal run, one line per mount, each asking its own y/N; an Adopt
    /// per launching config for the ownerless profiles.
    static func groupActions(_ kind: String, _ items: [DoctorItem]) -> [DoctorAction] {
        if ownerKinds.contains(kind) {
            return adoptActions(items)
        }
        let paths = kind == "mount_stale" ? items.compactMap(\.path) : []
        return paths.count > 1 ? [DoctorAction("Unmount All", paths.map(unmountCommand).joined(separator: "\n"))] : []
    }

    /// `jit unmount <path>` as the terminal runs it: the home-relative path
    /// when the shell reads it as written, the full path single-quoted
    /// when it holds a space or anything else the shell would act on.
    static func unmountCommand(_ path: String) -> String {
        let shown = homePath(path)
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+@%,:=~")
        if shown.unicodeScalars.allSatisfy(plain.contains), !shown.dropFirst().contains("~") {
            return "jit unmount \(shown)"
        }
        return "jit unmount '" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
            return originRow(item)
        case _ where ownershipKinds.contains(item.kind):
            return ownershipRow(item)
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
        case "pointer_missing":
            item.file != nil && item.path != nil
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
