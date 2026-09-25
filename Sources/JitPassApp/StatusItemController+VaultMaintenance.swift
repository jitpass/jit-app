// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The vault as a whole: orphans, backups, export, import, rekey. Each
/// destructive one runs with `--yes` only after a dialog here that asks
/// what jit's own y/N would ask, in the user's words rather than as a
/// command line; the passphrases go to jit through stdin.
extension StatusItemController {
    /// Prompt-free, so it runs when the sheet opens and after every delete.
    func loadOrphans() {
        model.vaultOrphans = nil
        Task.detached {
            let result = Result { try JitCLI.vaultOrphans() }
            await MainActor.run { [weak self] in
                switch result {
                case let .success(orphans): self?.model.vaultOrphans = orphans
                case let .failure(error): self?.model.vaultMessage = Format.error(error)
                }
            }
        }
    }

    /// `jit vault orphans --prune --yes`, which is the only command that
    /// clears a stale mount registration and deletes every orphaned secret
    /// in the same pass. The dialog is worded from a listing taken right
    /// here: the sheet's own list can be as old as the sheet, and what the
    /// user is told goes must be what goes. Orphaned secrets on their own
    /// are deleted through `jit vault rm` from the sheet's selection.
    func clearStaleMounts() {
        guard model.vaultBusy == nil else {
            return
        }
        let fresh: VaultOrphans
        do {
            fresh = try JitCLI.vaultOrphans()
        } catch {
            model.vaultMessage = Format.error(error)
            return
        }
        model.vaultOrphans = fresh
        let confirmation = fresh.staleMountConfirmation()
        guard Self.confirmDeletion(confirmation) else {
            return
        }
        runVault("the mount registrations", work: { JitCLI.execute(VaultOrphans.pruneArguments) }, then: { [weak self] output in
            self?.model.scanStale = true
            self?.notice(Self.lastLine(output, or: "cleared"))
            self?.loadOrphans()
        })
    }

    /// A deletion's dialog. The delete button comes first and is the
    /// default, except for a break-profiles delete: there no button takes
    /// Return, so Return never breaks a profile, and Cancel keeps Escape.
    /// With no button it only informs. `reveal` puts a link under the
    /// text that shows the file it is about in Finder, dialog still up.
    static func confirmDeletion(_ confirmation: DeleteConfirmation, reveal: RevealLink? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.accessoryView = reveal.map(RevealButton.init)
        alert.alertStyle = confirmation.button == nil || !confirmation.destructive ? .informational : .warning
        guard let button = confirmation.button else {
            alert.addButton(withTitle: "OK")
            alert.runFrontmost()
            return false
        }
        let delete = alert.addButton(withTitle: button)
        let cancel = alert.addButton(withTitle: "Cancel")
        // Red on the button that deletes, because colour carries state
        // here and this is the irreversible one; the system accent would
        // paint it the same blue as Done. A break-profiles delete goes
        // further: it takes no Return at all, so Return cannot break a
        // profile, and Cancel keeps Escape.
        delete.hasDestructiveAction = confirmation.destructive
        if confirmation.breaks {
            delete.keyEquivalent = ""
            cancel.keyEquivalent = "\u{1b}"
        }
        return alert.runFrontmost() == .alertFirstButtonReturn
    }

    /// jit's closing line ("Deleted 3 orphaned secrets."), for the notice.
    nonisolated static func lastLine(_ output: String, or fallback: String) -> String {
        let line = output.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? fallback : line
    }

    /// `jit vault prune --yes`: every migrate backup but the newest per
    /// file, after the dialog.
    func pruneBackups() {
        let count = model.vaultListing?.backups.count ?? 0
        let alert = NSAlert()
        alert.messageText = "Prune \(count) migrate backup\(count == 1 ? "" : "s")?"
        alert.informativeText = "Every backup but the newest per file is deleted for good; "
            + "jit migrate undo can then only restore that one. Touch ID follows."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Prune")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runVault("backups", work: { JitCLI.execute(["vault", "prune", "--yes"]) }, then: { [weak self] _ in
            self?.notice("backups pruned")
        })
    }

    /// Save panel, passphrase typed twice, `jit vault export <file> --stdin`.
    func exportVault() {
        guard let (path, passphrase) = askExport() else {
            return
        }
        runVault(
            "export",
            refresh: false,
            work: { JitCLI.execute(["vault", "export", path, "--stdin"], stdin: passphrase) },
            then: { [weak self] _ in
                self?.notice("exported to " + Format.home(path))
            }
        )
    }

    /// The export's save panel and passphrase, typed twice; nil when either
    /// was cancelled. The move sheet's Save Recovery File… asks the same.
    func askExport() -> (path: String, passphrase: String)? {
        let save = NSSavePanel()
        save.title = "Export the vault"
        save.nameFieldStringValue = "jit-vault-\(Format.dateStamp()).export"
        save.canCreateDirectories = true
        guard save.runFrontmost() == .OK, let url = save.url else {
            return nil
        }
        guard let passphrase = DoctorDialogs.askPassphrase(
            "Choose a passphrase for the export file. It is needed to import it.", title: "Export"
        ) else {
            return nil
        }
        return (url.path, passphrase)
    }

    /// Open panel, the passphrase, a dialog about overwrites, then
    /// `jit vault import <file> --stdin --yes`.
    func importVault() {
        let open = NSOpenPanel()
        open.title = "Import a vault export"
        open.canChooseFiles = true
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        guard open.runFrontmost() == .OK, let url = open.url else {
            return
        }
        guard let passphrase = DoctorDialogs.askSecret("The passphrase the export was made with.", title: "Import") else {
            return
        }
        let path = url.path
        let alert = NSAlert()
        alert.messageText = "Import \(url.lastPathComponent)?"
        alert.informativeText = "Every secret in the file is stored. A secret already at the same path is overwritten, "
            + "its current value archived first, so that much is reversible. Touch ID follows."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runVault(
            "import",
            work: { JitCLI.execute(["vault", "import", path, "--stdin", "--yes"], stdin: passphrase) },
            then: { [weak self] _ in
                self?.model.scanStale = true
                self?.notice("imported " + url.lastPathComponent)
            }
        )
    }

    /// `jit vault rekey --yes` after the dialog quoting what the help says:
    /// safe to interrupt, re-running finishes it.
    func rekeyVault() {
        let alert = NSAlert()
        alert.messageText = "Rekey the vault?"
        alert.informativeText = "A new master key is generated and every secret is re-wrapped under it. "
            + "Values are never decrypted to disk. Safe to interrupt: re-running finishes it. Touch ID follows."
        alert.addButton(withTitle: "Rekey")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runVault("rekey", work: { JitCLI.execute(["vault", "rekey", "--yes"]) }, then: { [weak self] _ in
            self?.notice("rekeyed")
        })
    }

    /// `jit vault duplicates --format json`, after a dialog saying what it
    /// costs: every value is decrypted to compare, so the unlock and one
    /// Touch ID per gated class (the consent sheet stays out of the way
    /// for a process the app spawned). The result opens as a sheet.
    func compareDuplicates() {
        let alert = NSAlert()
        alert.messageText = "Compare every secret?"
        alert.informativeText = "Every stored value is decrypted in memory to find copies of the same file. Nothing is changed."
            + "\n\nTouch ID follows, once per credential class the consent gate covers; a 1Password link asks 1Password too."
        alert.addButton(withTitle: "Compare")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runVault("duplicates", refresh: false, work: { JitCLI.vaultDuplicates() }, then: { [weak self] report in
            self?.model.vaultDuplicates = report
            self?.model.vaultDuplicatesAt = Date()
            self?.model.vaultSheet = .duplicates
        })
    }

    /// How old a comparison may be and still word the prune's dialog.
    /// Comparing again costs the unlock and a Touch ID per class, so a
    /// comparison the user has just run counts as fresh; one read while the
    /// sheet sat open for longer is run again first.
    static let duplicatesFreshFor: TimeInterval = 60

    /// `jit vault duplicates --prune --yes`: the stale copies whose origin
    /// is gone and which nothing uses, named in the dialog from a
    /// comparison at most `duplicatesFreshFor` old (run again first when
    /// older). The same Touch IDs again: pruning re-reads the values.
    func pruneDuplicates() {
        guard model.vaultDuplicates != nil, model.vaultBusy == nil else {
            return
        }
        let age = model.vaultDuplicatesAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if age < Self.duplicatesFreshFor, let report = model.vaultDuplicates {
            return confirmPruneDuplicates(report)
        }
        runVault("duplicates", refresh: false, work: { JitCLI.vaultDuplicates() }, then: { [weak self] report in
            self?.model.vaultDuplicates = report
            self?.model.vaultDuplicatesAt = Date()
            self?.confirmPruneDuplicates(report)
        })
    }

    private func confirmPruneDuplicates(_ report: VaultDuplicates) {
        guard Self.confirmDeletion(report.pruneConfirmation()) else {
            return
        }
        let count = report.prunablePaths.count
        runVault("duplicates", work: { JitCLI.execute(VaultDuplicates.pruneArguments) }, then: { [weak self] output in
            self?.model.vaultDuplicates = nil
            self?.model.vaultDuplicatesAt = nil
            self?.model.vaultSheet = nil
            self?.model.scanStale = true
            let deleted = output.split(separator: "\n").last { $0.hasPrefix("Deleted ") }.map(String.init)
            self?.notice(deleted ?? "\(count) stale secret\(count == 1 ? "" : "s") pruned")
        })
    }
}
