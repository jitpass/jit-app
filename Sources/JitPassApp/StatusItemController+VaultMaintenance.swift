// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The vault as a whole: orphans, backups, export, import, rekey. Each
/// destructive one runs with `--yes` only after a dialog here that names
/// the command; the passphrases go to jit through stdin.
extension StatusItemController {
    /// Prompt-free, so it runs when the sheet opens and after a prune.
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

    /// `jit vault orphans --prune --yes` after a dialog listing every path
    /// it deletes and every stale mount it clears, as jit lists them right
    /// before the dialog: the sheet's list can be as old as the sheet. The
    /// listing is prompt-free and quick, so it runs here, synchronously.
    func pruneOrphans() {
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
        guard Self.confirmDeletion(fresh.pruneConfirmation()) else {
            return
        }
        runVault("orphans", work: { JitCLI.execute(VaultOrphans.pruneArguments) }, then: { [weak self] output in
            self?.notice(Self.lastLine(output, or: "orphans pruned"))
            self?.loadOrphans()
        })
    }

    /// A deletion's dialog. The delete button comes first and is the
    /// default, except for a break-profiles delete: there no button takes
    /// Return, so Return never breaks a profile, and Cancel keeps Escape.
    /// With no button it only informs.
    static func confirmDeletion(_ confirmation: DeleteConfirmation) -> Bool {
        let alert = NSAlert()
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.alertStyle = confirmation.button == nil || !confirmation.destructive ? .informational : .warning
        guard let button = confirmation.button else {
            alert.addButton(withTitle: "OK")
            alert.runFrontmost()
            return false
        }
        let delete = alert.addButton(withTitle: button)
        let cancel = alert.addButton(withTitle: "Cancel")
        if confirmation.breaks {
            delete.hasDestructiveAction = true
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
        alert.informativeText = "This runs:\n\njit vault prune --yes\n\n"
            + "Every backup but the newest per file is deleted for good; jit migrate undo can then only restore that one. "
            + "Nothing asks again. Touch ID follows."
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
        let save = NSSavePanel()
        save.title = "Export the vault"
        save.nameFieldStringValue = "jit-vault-\(Format.dateStamp()).export"
        save.canCreateDirectories = true
        guard save.runFrontmost() == .OK, let url = save.url else {
            return
        }
        guard let passphrase = DoctorDialogs.askPassphrase(
            "Choose a passphrase for the export file. It is needed to import it.", title: "Export"
        ) else {
            return
        }
        let path = url.path
        runVault(
            "export",
            refresh: false,
            work: { JitCLI.execute(["vault", "export", path, "--stdin"], stdin: passphrase) },
            then: { [weak self] _ in
                self?.notice("exported to " + Format.home(path))
            }
        )
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
        alert.informativeText = "This runs:\n\njit vault import \(Format.home(path)) --yes\n\n"
            + "Every secret in the file is stored; a secret at the same path is overwritten, its current value archived first. "
            + "Nothing asks again. Touch ID follows."
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
        alert.informativeText = "This runs:\n\njit vault rekey --yes\n\n"
            + "A new master key is generated and every secret is re-wrapped under it. Values are never decrypted to disk. "
            + "Safe to interrupt: re-running finishes it. Touch ID follows."
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
        alert.informativeText = "This runs:\n\njit vault duplicates\n\n"
            + "jit decrypts every stored value in memory to find copies of the same file. "
            + "That takes the vault unlock plus one Touch ID per credential class the consent gate covers "
            + "(aws, git, shell history…); Settings › Protection › \"Ask before each tool's first credential use\" "
            + "is the switch for the per-class half. A 1Password link asks 1Password too. Nothing is changed."
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
