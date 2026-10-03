// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The result sheets that replaced jit's printout: a wrap, a cache clean,
/// an undo and a Verify, each built from the JSON jit 2.3.8 writes. jit's
/// words are on screen only under a failure; the rest is behind the
/// disclosure.
public extension ChangeSheet {
    /// After Wrap, Wrap Another Tool, or a wrap whose key was in a shell
    /// config. `stored` is the vault path the app's own `vault set` filled
    /// first, `protected` the shell config `jit migrate` rewrote first: each
    /// is a change that stands when the wrap after it failed. `verify` is
    /// set when the catalog has a check to run.
    static func wrapped(
        _ report: WrapReport, stored: String? = nil, protected: String? = nil, verify: Bool = false
    ) -> ChangeSheet {
        if report.kind == "native", let migrate = report.migrate {
            return nativeWrapped(report.tool, migrate, report: report.report)
        }
        let failed = !report.wrapped || !report.errors.isEmpty
        let notes = wrapNotes(report, stored: stored, protected: protected, failed: failed)
        let (title, sentence) = wrapHeadline(report, stored: stored, protected: protected, failed: failed, changed: notes.count > 1)
        return ChangeSheet(
            title: title, sentence: sentence, files: [], notes: notes, undo: [], report: report.report,
            verify: !failed && verify ? report.tool : nil
        )
    }

    /// Protect in Tools: a native tool's wrap is its migration, so the
    /// sheet is that migration's rows, worded for the tool.
    private static func nativeWrapped(_ tool: String, _ migrate: MigrateReport, report: String) -> ChangeSheet {
        var sheet = protect([migrate], report: report)
        if migrate.applied, migrate.errors.isEmpty {
            sheet.title = "Protected \(tool)" + (migrate.vaulted.isEmpty ? "" : " · " + secretsInVault(migrate.vaulted.count))
            sheet.sentence = "\(tool) keeps working: it gets its credentials from jit. Undo puts the file back from its backup."
        }
        return sheet
    }

    /// The failure first, then what stands: the step before the wrap, the
    /// key, variables still empty, secrets moved, and the shim.
    private static func wrapNotes(_ report: WrapReport, stored: String?, protected: String?, failed: Bool) -> [Note] {
        let tool = report.tool
        var notes: [Note] = []
        if failed {
            notes.append(Note(
                mark: .failed, name: "\(tool) was not wrapped", fact: "\(tool) still runs without jit.",
                verbatim: report.errors.last.map(lastLine) ?? lastLine(report.report)
            ))
        }
        if let protected {
            notes.append(Note(mark: .done, name: "Protected " + protected, fact: "Its key moved to the vault; the file still sets it"))
        }
        let moved = report.key.map { $0.from == "file" || $0.from == "keyring" } ?? false
        if let stored, !moved {
            notes.append(Note(mark: .done, name: (stored.split(separator: "/").last.map(String.init) ?? stored) + " stored", fact: stored))
        }
        if let key = report.key, !failed || moved, let note = keyNote(key, tool: tool, stored: stored) {
            notes.append(note)
        }
        for inject in report.injects ?? [] where !inject.stored && stored != inject.vaultPath {
            notes.append(Note(
                mark: .left, name: inject.name + " has no value yet", fact: "Nothing is stored at " + (inject.vaultPath ?? inject.name)
            ))
        }
        if report.kind == "store" {
            if !failed {
                notes += storeNotes(report)
            }
            return notes
        }
        if !report.vaulted.isEmpty {
            notes.append(Note(mark: .done, name: secretsInVault(report.vaulted.count), fact: NameList.capped(report.vaulted)))
        }
        if !failed {
            notes += shimNotes(report)
        }
        return notes
    }

    /// A store wrap: where the login is now, then every tool of the
    /// family that runs through jit. `vaulted` is the store itself when
    /// the wrap moved it; empty and not logged out, it was already sealed.
    private static func storeNotes(_ report: WrapReport) -> [Note] {
        let store = report.store ?? report.tool
        var notes: [Note] = if report.storeLoggedOut {
            [Note(mark: .left, name: "No \(store) login yet", fact: "Your next \(store) login goes straight to the vault")]
        } else if let path = report.vaulted.first {
            [Note(mark: .done, name: "\(store)'s login moved to the vault", fact: "Nothing of it is left on disk · " + path)]
        } else {
            [Note(mark: .done, name: "\(store)'s login was already in the vault", fact: "Nothing of it is on disk")]
        }
        let family = storeFamily(report)
        notes.append(Note(
            mark: .done, name: NameList.spoken(family) + (family.count == 1 ? " now runs" : " now run") + " through jit",
            fact: report.pathAddedTo.map { "New terminals use " + (family.count == 1 ? "it" : "them") + ". jit added its line to " + $0 }
                ?? "Each run unseals the login, and seals it again after"
        ))
        return notes
    }

    /// The tools a store wrap shimmed, by the shims' names, the namesake
    /// first; the tool itself from an engine that lists none.
    static func storeFamily(_ report: WrapReport) -> [String] {
        let names = report.shims.map { ($0 as NSString).lastPathComponent }
        let lead = report.store ?? report.tool
        let ordered = names.filter { $0 == lead } + names.filter { $0 != lead }
        return ordered.isEmpty ? [report.tool] : ordered
    }

    /// Where a shim tool's key came from.
    private static func keyNote(_ key: WrapReport.Key, tool: String, stored: String?) -> Note? {
        switch key.from {
        case "file":
            Note(
                mark: .done, name: key.name + " moved to the vault",
                fact: "From " + (key.source ?? "its file") + (key.scrubbed ? ", now emptied" : "") + " · " + key.vaultPath
            )
        case "keyring":
            Note(mark: .done, name: key.name + " moved to the vault", fact: "Copied from \(tool)'s keyring · " + key.vaultPath)
        case "vault" where stored == nil:
            Note(mark: .done, name: key.name + " is in the vault", fact: "Already stored · " + key.vaultPath)
        case "none":
            Note(mark: .left, name: "No key stored yet", fact: "\(tool) runs without one until " + key.vaultPath + " holds it")
        default:
            nil
        }
    }

    /// The tool now runs through jit, and for a grant whether its file is
    /// there to serve.
    private static func shimNotes(_ report: WrapReport) -> [Note] {
        let tool = report.tool
        guard report.kind == "grant" else {
            return [Note(
                mark: .done, name: "\(tool) now runs through jit",
                fact: report.pathAddedTo.map { "New terminals use it. jit added its line to " + $0 } ?? "New terminals use it"
            )]
        }
        var notes = [Note(mark: .done, name: "\(tool) now runs through jit", fact: "It gets the \(report.grant ?? "") file on each run")]
        if report.grantMigrated == false {
            notes.append(Note(
                mark: .left, name: "That file isn't in the vault yet",
                fact: "Protect it in Findings. Until then \(tool) gets nothing from jit."
            ))
        }
        return notes
    }

    private static func wrapHeadline(
        _ report: WrapReport, stored: String?, protected: String?, failed: Bool, changed: Bool
    ) -> (String, String) {
        let tool = report.tool
        if !failed {
            let sentence = switch report.kind {
            case "grant": "\(tool) runs inside a jit grant, so it reads the real file and anything else reads a decoy."
            case "capture": "What \(tool) mints goes to the vault, not to a file."
            case "rungrant": "\(tool) runs inside a jit grant."
            case "store": report.storeLoggedOut
                ? "Each \(report.store ?? tool) login from now on is kept in the vault, not on disk."
                : "\(report.store ?? tool)'s login is in the vault. Each run unseals it for that run only."
            default: "\(tool)'s key is in the vault. jit hands it to \(tool) each time it runs."
            }
            let named = report.kind == "store" ? NameList.spoken(storeFamily(report)) : tool
            return ("Wrapped " + named, sentence)
        }
        if let stored {
            return ("Stored \(tool)'s key · the wrap failed", "The key is in the vault at \(stored).")
        }
        if let protected {
            return ("Protected \(protected) · the wrap failed", "The key is in the vault.")
        }
        return ("Wrapping \(tool) failed", changed ? "What changed below stays changed." : "Nothing was changed.")
    }

    /// After Clean AI agent caches: each file rewritten, what was left.
    static func caches(_ report: MigrateReport) -> ChangeSheet {
        let removed = report.caches.removed
        let left = report.caches.left
        let copies = removed.reduce(0) { $0 + ($1.copies ?? 0) }
        // From the files, not the copy count: jit may leave `copies` out,
        // and a run that only left files did not find the caches clean.
        let title = if !report.errors.isEmpty {
            "Cleaning did not finish"
        } else if !removed.isEmpty {
            "Cleaned " + (copies > 0 ? plural(copies, "copy", "copies") + " in " : "") + plural(removed.count, "file")
        } else if !left.isEmpty {
            "Nothing was cleaned · " + plural(left.count, "file") + " left for later"
        } else {
            "No AI agent cache holds a copy of a vaulted secret"
        }
        var notes: [Note] = []
        if !report.errors.isEmpty {
            notes.append(Note(
                mark: .failed, name: "Cleaning did not finish",
                fact: removed.isEmpty ? "Nothing was changed." : "What changed below stays changed, and Undo still restores it.",
                verbatim: VaultOrphans.capped(report.errors, NameList.shown)
            ))
        }
        if !left.isEmpty {
            let live = left.filter { $0.kind == "live" }
            let places = ScanWording.agentPlaces(left.map { (agent: $0.agent, area: $0.area) }).joined(separator: " and ")
            notes.append(Note(
                mark: .left,
                name: plural(left.count, "file") + " left in " + places,
                fact: live.first.map { "\($0.agent) is writing " + (live.count == 1 ? "it" : "them") + ". The next scan tries again." }
                    ?? left.compactMap(\.reason).first ?? "jit left it as it was."
            ))
        }
        return ChangeSheet(
            title: title,
            sentence: removed.isEmpty ? "Nothing was changed." :
                "Each copy of a vaulted secret is now a marker. Each file was backed up first.",
            files: removed.map {
                File(path: $0.path, fact: ([$0.agent, $0.area].filter { !$0.isEmpty } + [plural($0.copies ?? 0, "copy", "copies")])
                    .joined(separator: " · "))
            },
            notes: notes,
            undo: removed.map(\.path),
            report: report.report
        )
    }

    /// After Undo protecting: each file back from its backup, its secrets
    /// in plain text again. Protect Again is the one control that changes
    /// that, so it is the sheet's action instead of Undo.
    static func restored(_ report: UndoReport) -> ChangeSheet {
        let done = report.files.filter(\.restored)
        let failures = report.files.filter { !$0.restored }
        var notes: [Note] = []
        if !failures.isEmpty || !report.errors.isEmpty {
            let lines = failures.map { ($0.path as NSString).lastPathComponent + ": " + ($0.error ?? "not restored") }
            notes.append(Note(
                mark: .failed,
                name: failures.isEmpty ? "Undo did not finish" : plural(failures.count, "file") + " not restored",
                fact: (failures.count == 1 ? "It was" : "They were") + " left as " + (failures.count == 1 ? "it was." : "they were."),
                verbatim: VaultOrphans.capped(lines.isEmpty ? report.errors : lines, NameList.shown)
            ))
        }
        let title = done.isEmpty ? "Nothing was restored" : "Restored " + plural(done.count, "file")
        return ChangeSheet(
            title: title,
            sentence: done.isEmpty ? "No file was changed."
                : "Each file is back from its backup, so its secrets are in plain text on disk again.",
            files: done.map { File(path: $0.path, fact: restoredFact($0)) },
            notes: notes,
            undo: [],
            report: report.report,
            // Only a file with secrets of its own: an AI agent's cache file
            // restored by undoing a clean has none, and `jit migrate` on it
            // is not the sweep that cleaned it.
            again: done.filter { $0.action != "remove" && !$0.secrets.isEmpty }.map(\.path)
        )
    }

    /// What one restored file holds now.
    static func restoredFact(_ file: UndoReport.File) -> String {
        switch file.action {
        case "remove":
            return "Removed: the migration had created it"
        default:
            let names = file.secrets.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
            let back = file.action == "recreate" ? "Re-created from its backup" : "Back from its backup"
            guard !names.isEmpty else {
                return back
            }
            return NameList.capped(names) + " in plain text · " + (names.count == 1 ? "the copy stays" : "copies stay") + " in the vault"
        }
    }

    /// After Verify: does the tool work with the key jit holds? `status`
    /// and `output` are the check's; `printsSecret` (the catalog's
    /// verify_prints_secret) means the output is never kept, so there is
    /// no disclosure and no line under a failure. `gh` is gh's own JSON,
    /// when the tool is gh: its accounts become rows.
    static func verify(
        tool: String, hint: String, status: Int32, output: String, printsSecret: Bool, gh: GhAuthStatus? = nil
    ) -> ChangeSheet {
        let kept = printsSecret ? "" : output
        if let gh, !gh.accounts.isEmpty {
            return verifyGh(gh, output: kept)
        }
        guard status == 0 else {
            return ChangeSheet(
                title: "\(tool)'s check failed",
                sentence: "\(tool) ran with the key jit holds and stopped with an error.",
                files: [],
                notes: [Note(
                    mark: .failed,
                    name: hint + " exited with an error",
                    fact: printsSecret ? "Its output can hold a secret, so JitPass doesn't show it." : "\(tool) said:",
                    verbatim: printsSecret ? nil : lastLine(output)
                )],
                undo: [], report: kept, reportLabel: "\(tool)'s output"
            )
        }
        return ChangeSheet(
            title: "\(tool) works",
            sentence: printsSecret
                ? "Its check prints a secret, so JitPass doesn't show what it printed."
                : hint + " finished without an error, using the key jit holds.",
            files: [], notes: [], undo: [], report: kept, reportLabel: "\(tool)'s output"
        )
    }

    private static func verifyGh(_ gh: GhAuthStatus, output: String) -> ChangeSheet {
        let accounts = gh.accounts
        guard let active = accounts.first(where: \.active) else {
            return ChangeSheet(
                title: "gh's check failed", sentence: "gh isn't using any of the accounts signed in on this Mac.",
                files: [], notes: [Note(mark: .failed, name: "No active account", fact: "Run gh auth switch, or wrap gh again.")],
                undo: [], report: output, reportLabel: "gh's output"
            )
        }
        let broken = accounts.filter { $0.state != "success" }
        let fromJit = active.tokenSource == "GH_TOKEN"
        var notes = broken.filter(\.active).map {
            Note(mark: .failed, name: $0.host + " rejected the key", fact: "gh signed in as \($0.login), and the key didn't work.")
        }
        notes += accounts.map { account in
            Note(
                mark: account.state != "success" ? .left : account.active ? .done : .info,
                name: account.login + (account.active ? " · active" : ""),
                fact: [account.host, keyPlace(account.tokenSource), account.scopes ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }
        let others = accounts.count > 1 ? " \(accounts.count) accounts are signed in on this Mac." : ""
        let ok = broken.first(where: \.active) == nil
        return ChangeSheet(
            title: ok ? "gh works · signed in as \(active.login)" : "gh's check failed",
            sentence: ok ? (fromJit ? "gh used the key jit gave it." : "gh used the key in its keyring, not jit's.") + others
                : "gh ran with the key jit holds and stopped with an error.",
            files: [], notes: notes, undo: [], report: output, reportLabel: "gh's output"
        )
    }

    private static func keyPlace(_ source: String?) -> String {
        switch source {
        case "GH_TOKEN": "key from jit"
        case "keyring": "key in gh's keyring"
        case let other?: "key from " + other
        case nil: ""
        }
    }

    private static func secretsInVault(_ n: Int) -> String {
        n == 1 ? "1 secret is in the vault" : "\(n) secrets are in the vault"
    }

    private static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) " + (n == 1 ? one : many ?? one + "s")
    }

    /// The last non-empty line: what a failed command says last is its
    /// error.
    static func lastLine(_ text: String) -> String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? ""
    }
}
