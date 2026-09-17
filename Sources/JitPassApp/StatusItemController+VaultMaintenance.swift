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
    /// it deletes and every stale mount it clears.
    func pruneOrphans() {
        guard let orphans = model.vaultOrphans, !orphans.isEmpty else {
            return
        }
        var lines = orphans.orphans.map(\.path)
        lines += orphans.staleMounts.map { "mount registration " + Format.home($0.mountPath) }
        let alert = NSAlert()
        alert.messageText = "Prune \(orphans.orphans.count) orphaned secret\(orphans.orphans.count == 1 ? "" : "s")?"
        alert.informativeText = "This runs:\n\njit vault orphans --prune --yes\n\nIt deletes for good:\n"
            + lines.joined(separator: "\n")
            + "\n\nA secret used only by a project you are not in and have not mounted looks orphaned too; "
            + "check the origins first. Nothing asks again. Touch ID follows."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Prune")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        runVault("orphans", work: { JitCLI.execute(["vault", "orphans", "--prune", "--yes"]) }, then: { [weak self] _ in
            self?.notice("orphans pruned")
            self?.loadOrphans()
        })
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
        guard alert.runModal() == .alertFirstButtonReturn else {
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
        guard save.runModal() == .OK, let url = save.url else {
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
        guard open.runModal() == .OK, let url = open.url else {
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
        guard alert.runModal() == .alertFirstButtonReturn else {
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
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        runVault("rekey", work: { JitCLI.execute(["vault", "rekey", "--yes"]) }, then: { [weak self] _ in
            self?.notice("rekeyed")
        })
    }
}
