// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Doctor's ownership kinds (jit 2.0, jitpass/jit
/// internal/cli/doctorownership.go), read from the engine's map of what
/// uses each profile and what points at each secret. The words are the
/// user's: a tool (an MCP server, aws, kubectl, a wrapped CLI) uses a
/// profile, a config is the file that starts tools, and a profile's
/// record is its note of which configs use it.
///
/// - profile_missing: a config names a profile no store holds. No button:
///   the fix is an edit to a file jit doesn't own, which the engine's own
///   advice, said once under the rows of one tool kind, names.
/// - pointer_missing: a jit:// pointer names a missing secret. Set Value.
/// - config_deleted, config_not_recorded: an MCP profile whose record
///   names no live config. One Attach per config that starts it, on the
///   group, confirmed from `jit profile attach --dry-run`.
/// - no_known_tool: a global profile nothing known uses. Remove Profile,
///   confirmed from `jit profile rm --dry-run`.
///
/// A pre-release jit 2.0 named these launcher_broken, owner_gone, no_owner
/// and unlaunched; `currentKind` reads those as the new names.
extension DoctorAdvice {
    static let ownershipKinds: Set<String> = [
        "profile_missing", "pointer_missing", "config_deleted", "config_not_recorded", "no_known_tool"
    ]
    static let recordKinds: Set<String> = ["config_deleted", "config_not_recorded"]

    /// The kinds a pre-release jit 2.0 named differently, old to new.
    static let renamedKinds = [
        "launcher_broken": "profile_missing",
        "owner_gone": "config_deleted",
        "no_owner": "config_not_recorded",
        "unlaunched": "no_known_tool"
    ]

    /// The kind as this app knows it: a pre-release name read as its new one.
    static func currentKind(_ kind: String) -> String {
        renamedKinds[kind] ?? kind
    }

    static let ownershipTitles: [String: (title: String, note: String?)] = [
        "profile_missing": (
            "Missing profiles",
            "A config names a jit profile that doesn't exist, so that tool fails."
        ),
        "pointer_missing": (
            "Missing pointed-to secrets",
            "A file points at a secret the vault doesn't hold, so the tool that reads it gets nothing."
        ),
        "config_deleted": (
            "Profiles recording a deleted config",
            "The config they record is deleted, and another one starts their tools now. "
                + "Attach records that config instead; no secret changes."
        ),
        "config_not_recorded": (
            "Profiles with no config recorded",
            "A config starts their tools, but none is recorded for them. Attach records it; no secret changes."
        ),
        "no_known_tool": (
            "No known tool",
            "Nothing jit can see uses these. It can't see scripts or aliases, "
                + "so remove one only if you no longer use it."
        )
    ]

    static let ownershipBuilders: [String: Builder] = [
        // The fix is an edit to a file jit doesn't own; the run's note,
        // the engine's own advice, says which.
        "profile_missing": { _ in [] },
        "pointer_missing": { item in [setValue("Set Value", item)] },
        // `jit migrate forget <file>`, titled by what it does rather than
        // the generic "Run" every unrecognised fix gets. Destructive, so
        // the app confirms; no Touch ID, because no secret is read.
        "stale_pointers": { item in
            (item.fixes ?? []).map { fix in
                guard fix.argv.starts(with: ["migrate", "forget"]) else {
                    return generic(fix)
                }
                let targets = Array(fix.argv.dropFirst(2))
                // "Delete File", not "Delete Record": the row shows a path
                // and the sibling button is Edit, which opens that same
                // file. "Record" was jit's noun for the thing, not the
                // reader's, and it made the pair read as two different
                // objects.
                return DoctorAction(
                    "Delete File", fix.command, destructive: true,
                    argv: [["migrate", "forget", "--yes"] + targets]
                )
            }
        },
        // One Attach per config, on the group: see attachActions.
        "config_deleted": { _ in [] },
        "config_not_recorded": { _ in [] },
        "no_known_tool": removeProfile
    ]

    /// Actions for the whole group: every stale mount unmounted in one
    /// terminal run, one line per mount, each asking its own y/N; an Attach
    /// per config that starts the group's profiles.
    static func groupActions(_ kind: String, _ items: [DoctorItem], among all: [DoctorItem]) -> [DoctorAction] {
        if recordKinds.contains(kind) {
            return attachActions(items, among: all)
        }
        let paths = kind == "mount_stale" ? items.compactMap(\.path) : []
        return paths.count > 1 ? [DoctorAction("Unmount All", paths.map(unmountCommand).joined(separator: "\n"))] : []
    }

    // Unmount stays in the terminal, alone among the fixes, and Unmount
    // All with it. The app would have to pass --yes, and that flag would
    // also answer the y/N guarding a PLAINTEXT write-back if the mount's
    // profile came back between the check and the click. jit asking once
    // more, in front of the user, is the point of that prompt.

    /// One Attach per config the rows' fixes attach, in first-seen order:
    /// a profile two configs start is attached to the one doctor names.
    /// The argv is a fallback only: the dialog runs the names its dry run
    /// listed.
    ///
    /// Attaching a config takes every profile it starts, in both record
    /// groups, so each button counts them all across `all` ("Attach 7"),
    /// and the same config's button reads the same in either group: one
    /// that counted only its own group's 2 read as if it attached only
    /// those. Named by config ("Attach 7 for Security-Ops/.mcp.json") when
    /// the report has more than one.
    static func attachActions(_ items: [DoctorItem], among all: [DoctorItem]) -> [DoctorAction] {
        var targets: [(config: String, command: String)] = []
        for item in items {
            for target in attachTargets(item) where !targets.contains(where: { $0.config == target.config }) {
                targets.append(target)
            }
        }
        var counts: [String: Int] = [:]
        for item in all where recordKinds.contains(item.kind) {
            for config in Set(attachTargets(item).map(\.config)) {
                counts[config, default: 0] += 1
            }
        }
        let one = Set(counts.keys).union(targets.map(\.config)).count == 1
        return targets.map { config, command in
            let count = counts[config] ?? 0
            let verb = count > 1 ? "Attach \(count)" : "Attach"
            return DoctorAction(
                one ? verb : verb + " for " + ellipsis(configShortName(config), 40), command,
                argv: [["profile", "attach", "--yes", config]], planned: .attach(config: config)
            )
        }
    }

    /// A config as a button names it: its folder and file
    /// ("Security-Ops/.mcp.json"), or the ~ path when that is all it is
    /// ("~/.claude.json"). `home` is for a dialog that shortens with its own.
    static func configShortName(_ config: String, home: String? = nil) -> String {
        let shown = home.map { VaultRmPlan.short(config, $0) } ?? homePath(config)
        let parts = shown.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count <= 2 ? shown : parts.suffix(2).joined(separator: "/")
    }

    /// The config a record row's fix attaches, and the command as the
    /// engine wrote it. Only a fix that is exactly `profile attach
    /// <config>` (a pre-release jit's `profile adopt <config>` too):
    /// anything else is not the button this is.
    static func attachTargets(_ item: DoctorItem) -> [(config: String, command: String)] {
        guard let fixes = item.fixes else {
            return item.config.map { [($0, "jit profile attach " + homePath($0))] } ?? []
        }
        return fixes.compactMap { fix in
            guard !fix.external, fix.argv.count == 3, fix.argv[0] == "profile", ["attach", "adopt"].contains(fix.argv[1]) else {
                return nil
            }
            return (fix.argv[2], fix.command)
        }
    }

    /// Remove Profile on a no-known-tool row: `jit profile rm`, confirmed
    /// from its dry run. Never offered when the engine's fixes leave it out.
    static func removeProfile(_ item: DoctorItem) -> [DoctorAction] {
        guard let name = item.profile else {
            return []
        }
        let fix = item.fixes?.first { !$0.external && $0.argv.starts(with: ["profile", "rm"]) }
        if item.fixes != nil, fix == nil {
            return []
        }
        return [DoctorAction(
            "Remove Profile", fix?.command ?? "jit profile rm \(name)", destructive: true,
            argv: [["profile", "rm", "--yes", name]], planned: .removeProfile(name: name, manifest: item.path?.nilIfEmpty)
        )]
    }

    /// What every row of a record group shares, said once under the
    /// title, one line each as `jit doctor` prints them: the deleted config
    /// the profiles record ("Recorded config ~/a/.mcp.json is deleted"),
    /// then the config that starts their tools ("Now started by
    /// ~/b/.mcp.json"). Two lines, not one sentence: a sentence of two
    /// paths wrapped mid-path. Empty when the rows differ; each row then
    /// says its own.
    static func sharedFacts(_ kind: String, _ items: [DoctorItem]) -> [DoctorFact] {
        guard recordKinds.contains(kind), let first = items.first,
              items.allSatisfy({ recordKey($0) == recordKey(first) })
        else {
            return []
        }
        let configs = first.configs ?? first.config.map { [$0] } ?? []
        guard kind == "config_deleted" else {
            return [DoctorFact("Started by \(pathsPhrase(configs))", path: configs.first)]
        }
        let recorded = recordedFiles(first.owners ?? [])
        return [
            DoctorFact("Recorded config \(pathsPhrase(recorded)) is deleted", path: recorded.first),
            DoctorFact("Now started by \(pathsPhrase(configs))", path: configs.first)
        ]
    }

    /// An ownership row: the thing that is wrong, in the fewest words.
    static func ownershipRow(_ item: DoctorItem) -> String {
        switch item.kind {
        case "profile_missing":
            guard let launcher = item.launchers?.first, let profile = item.profile else {
                return item.summary
            }
            return homePath(launcher.file) + (launcher.detail.map { " " + $0 } ?? "") + " names " + profile
        case "pointer_missing":
            guard let file = item.file, let path = item.path else {
                return item.summary
            }
            return "\(homePath(file)) · \(path)"
        case "no_known_tool":
            guard let profile = item.profile else {
                return item.summary
            }
            var text = "\(profile) · \(secretsPhrase(item.secrets ?? 0, missing: item.secretsMissing ?? 0))"
            if let origin = item.origin {
                text += " · made from \(homePath(origin)), now gone"
            }
            return text
        case _ where recordKinds.contains(item.kind):
            guard let profile = item.profile else {
                return item.summary
            }
            return profile + (toolsPhrase(item.launchers).map { " · " + $0 } ?? "")
        default:
            return item.profile ?? item.summary
        }
    }

    /// "tool okta-mcp-server", "tools caido and urlscan": the MCP servers
    /// that use a record row's profile, each once; nil when it names none.
    static func toolsPhrase(_ launchers: [DoctorLauncher]?) -> String? {
        var names: [String] = []
        for launcher in launchers ?? [] where launcher.kind == "mcp" {
            if let name = launcher.detail, !names.contains(name) {
                names.append(name)
            }
        }
        guard let last = names.last else {
            return nil
        }
        return names.count == 1 ? "tool " + last : "tools " + names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// "1 secret", "2 secrets, both missing", as `jit doctor` counts them.
    static func secretsPhrase(_ count: Int, missing: Int) -> String {
        let noun = count == 1 ? "1 secret" : "\(count) secrets"
        switch (count, missing) {
        case (0, _): return "no secrets"
        case (_, 0): return noun
        case let (all, gone) where gone < all: return "\(noun), \(gone) missing"
        case (1, _): return "1 secret, missing"
        case (2, _): return "2 secrets, both missing"
        default: return "\(noun), all missing"
        }
    }

    /// The config files a profile's record names, block scopes ("#dir")
    /// dropped. The engine's JSON still calls the record `owners`.
    static func recordedFiles(_ record: [String]) -> [String] {
        var files: [String] = []
        for entry in record {
            let file = recordedFile(entry)
            if !files.contains(file) {
                files.append(file)
            }
        }
        return files
    }

    static func recordedFile(_ entry: String) -> String {
        entry.firstIndex(of: "#").map { String(entry[..<$0]) } ?? entry
    }

    /// "~/a/.mcp.json", "~/a/.mcp.json and 2 more".
    static func pathsPhrase(_ paths: [String]) -> String {
        guard let first = paths.first else {
            return "?"
        }
        return homePath(first) + (paths.count > 1 ? " and \(paths.count - 1) more" : "")
    }

    private static func recordKey(_ item: DoctorItem) -> [String] {
        (item.kind == "config_deleted" ? recordedFiles(item.owners ?? []) : []) + ["\u{0}"] + (item.configs ?? [])
    }

    static func ellipsis(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}

public extension DoctorGroup {
    /// The row as this group shows it: a record row names its configs only
    /// when the group's note could not say them once for all.
    func rowText(_ item: DoctorItem) -> String {
        let base = DoctorAdvice.rowText(item)
        guard DoctorAdvice.recordKinds.contains(kind), DoctorAdvice.sharedFacts(kind, items).isEmpty else {
            return base
        }
        var text = base + " · started by " + DoctorAdvice.pathsPhrase(item.configs ?? item.config.map { [$0] } ?? [])
        if kind == "config_deleted" {
            text += " · recorded config " + DoctorAdvice.pathsPhrase(DoctorAdvice.recordedFiles(item.owners ?? [])) + " is deleted"
        }
        return text
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
