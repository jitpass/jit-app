// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Doctor's ownership kinds (jit 2.0, jitpass/jit
/// internal/cli/doctorownership.go), read from the engine's launcher map:
/// what starts each profile and what points at each secret.
///
/// - launcher_broken: a config names a profile no store holds. No button:
///   the fix is an edit to a file jit doesn't own, which the row's note,
///   the engine's own sentence, names.
/// - pointer_missing: a jit:// pointer names a missing secret. Set Value.
/// - owner_gone, no_owner: an MCP profile no live config owns. One Adopt
///   per launching config, on the group, confirmed from
///   `jit profile adopt --dry-run`.
/// - unlaunched: a global profile nothing known starts. Remove Profile,
///   confirmed from `jit profile rm --dry-run`.
extension DoctorAdvice {
    static let ownershipKinds: Set<String> = ["launcher_broken", "pointer_missing", "owner_gone", "no_owner", "unlaunched"]
    static let ownerKinds: Set<String> = ["owner_gone", "no_owner"]

    static let ownershipTitles: [String: (title: String, note: String?)] = [
        "launcher_broken": (
            "Broken launchers",
            "A config names a jit profile that doesn't exist, so the tool it starts fails."
        ),
        "pointer_missing": (
            "Missing pointed-to secrets",
            "A file points at a secret the vault doesn't hold, so the tool that reads it gets nothing."
        ),
        "owner_gone": (
            "Profiles whose owner is gone",
            "The MCP config that made them is gone, and another one launches them. "
                + "Adopt makes that config their owner; no secret changes."
        ),
        "no_owner": (
            "Profiles with no owner",
            "An MCP config launches them, but none is recorded as their owner. "
                + "Adopt makes it their owner; no secret changes."
        ),
        "unlaunched": (
            "No known launcher",
            "Nothing jit can see starts these. It can't see scripts or aliases, "
                + "so remove one only if you no longer use it."
        )
    ]

    static let ownershipBuilders: [String: Builder] = [
        // The fix is an edit to a file jit doesn't own; the row's note,
        // the engine's own sentence, says which.
        "launcher_broken": { _ in [] },
        "pointer_missing": { item in [setValue("Set Value", item)] },
        // One Adopt per launching config, on the group: see adoptActions.
        "owner_gone": { _ in [] },
        "no_owner": { _ in [] },
        "unlaunched": removeProfile
    ]

    /// One Adopt per config the rows' fixes adopt into, in first-seen
    /// order: a profile two configs launch is adopted by the one doctor
    /// names. Titled "Adopt" when there is one, else by config. The argv
    /// is a fallback only: the dialog runs the names its dry run listed.
    static func adoptActions(_ items: [DoctorItem]) -> [DoctorAction] {
        var targets: [(config: String, command: String)] = []
        for item in items {
            for target in adoptTargets(item) where !targets.contains(where: { $0.config == target.config }) {
                targets.append(target)
            }
        }
        let one = targets.count == 1
        return targets.map { config, command in
            DoctorAction(
                one ? "Adopt" : "Adopt for " + ellipsis(homePath(config), 40), command,
                argv: [["profile", "adopt", "--yes", config]], planned: .adopt(config: config)
            )
        }
    }

    /// The config an owner row's fix adopts into, and the command as the
    /// engine wrote it. Only a fix that is exactly `profile adopt <config>`:
    /// anything else is not the button this is.
    static func adoptTargets(_ item: DoctorItem) -> [(config: String, command: String)] {
        guard let fixes = item.fixes else {
            return item.config.map { [($0, "jit profile adopt " + homePath($0))] } ?? []
        }
        return fixes.compactMap { fix in
            guard !fix.external, fix.argv.count == 3, fix.argv.starts(with: ["profile", "adopt"]) else {
                return nil
            }
            return (fix.argv[2], fix.command)
        }
    }

    /// Remove Profile on an unlaunched row: `jit profile rm`, confirmed
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
            argv: [["profile", "rm", "--yes", name]], planned: .removeProfile(name: name)
        )]
    }

    /// What every row of an owner group shares, said once under the title:
    /// the gone owner and the launching config. Nil when the rows differ;
    /// each row then says its own.
    static func sharedFacts(_ kind: String, _ items: [DoctorItem]) -> String? {
        guard ownerKinds.contains(kind), let first = items.first,
              items.allSatisfy({ ownerKey($0) == ownerKey(first) })
        else {
            return nil
        }
        let launched = "Launched by \(pathsPhrase(first.configs ?? first.config.map { [$0] } ?? []))."
        guard kind == "owner_gone" else {
            return launched
        }
        return "Made by \(pathsPhrase(ownerFiles(first.owners ?? []))), now gone. " + launched
    }

    /// An ownership row: the thing that is wrong, in the fewest words.
    static func ownershipRow(_ item: DoctorItem) -> String {
        switch item.kind {
        case "launcher_broken":
            guard let launcher = item.launchers?.first, let profile = item.profile else {
                return item.summary
            }
            return homePath(launcher.file) + (launcher.detail.map { " " + $0 } ?? "") + " names " + profile
        case "pointer_missing":
            guard let file = item.file, let path = item.path else {
                return item.summary
            }
            return "\(homePath(file)) · \(path)"
        case "unlaunched":
            guard let profile = item.profile else {
                return item.summary
            }
            var text = "\(profile) · \(secretsPhrase(item.secrets ?? 0, missing: item.secretsMissing ?? 0))"
            if let origin = item.origin {
                text += " · made from \(homePath(origin)), now gone"
            }
            return text
        default:
            return item.profile ?? item.summary
        }
    }

    /// A second line under the row, where the engine's advice is specific
    /// to the row: a broken launcher's "what to do", which differs by the
    /// kind of file ("delete that [profile] block", "drop that jit run
    /// layer"). The first clause, what fails, the group note already says.
    public static func rowNote(_ item: DoctorItem) -> String? {
        guard item.kind == "launcher_broken", let action = item.action, !action.isEmpty else {
            return nil
        }
        let clauses = action.components(separatedBy: "; ")
        let advice = clauses.count > 1 ? clauses.dropFirst().joined(separator: "; ") : action
        return advice.prefix(1).uppercased() + advice.dropFirst()
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

    /// The config files an owner list names, block scopes ("#dir") dropped.
    static func ownerFiles(_ owners: [String]) -> [String] {
        var files: [String] = []
        for owner in owners {
            let file = ownerFile(owner)
            if !files.contains(file) {
                files.append(file)
            }
        }
        return files
    }

    static func ownerFile(_ owner: String) -> String {
        owner.firstIndex(of: "#").map { String(owner[..<$0]) } ?? owner
    }

    /// "~/a/.mcp.json", "~/a/.mcp.json and 2 more".
    static func pathsPhrase(_ paths: [String]) -> String {
        guard let first = paths.first else {
            return "?"
        }
        return homePath(first) + (paths.count > 1 ? " and \(paths.count - 1) more" : "")
    }

    private static func ownerKey(_ item: DoctorItem) -> [String] {
        (item.kind == "owner_gone" ? ownerFiles(item.owners ?? []) : []) + ["\u{0}"] + (item.configs ?? [])
    }

    static func ellipsis(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}

public extension DoctorGroup {
    /// The row as this group shows it: an owner row names its configs only
    /// when the group's note could not say them once for all.
    func rowText(_ item: DoctorItem) -> String {
        let base = DoctorAdvice.rowText(item)
        guard DoctorAdvice.ownerKinds.contains(kind), DoctorAdvice.sharedFacts(kind, items) == nil else {
            return base
        }
        var text = base + " · launched by " + DoctorAdvice.pathsPhrase(item.configs ?? item.config.map { [$0] } ?? [])
        if kind == "owner_gone" {
            text += " · made by " + DoctorAdvice.pathsPhrase(DoctorAdvice.ownerFiles(item.owners ?? []))
        }
        return text
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
