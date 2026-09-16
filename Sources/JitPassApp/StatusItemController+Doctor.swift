// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Doctor: the panel row and the findings window.
extension StatusItemController {
    var doctorActions: DoctorActions {
        DoctorActions(
            recheck: { [weak self] in self?.runDoctor() },
            openInTerminal: { [weak self] in self?.runInTerminal("jit doctor") },
            run: { [weak self] command in self?.runInTerminal(command) },
            runWithChosenPath: { [weak self] command in self?.runWithChosenPath(command) },
            deleteProfile: { [weak self] name in self?.confirmDeleteProfile(name) }
        )
    }

    /// A command with a <file> or <path> placeholder cannot run as written.
    /// An export names a file to CREATE, so it gets a save panel; everything
    /// else names something that exists, so an open panel that accepts a
    /// file or a folder. The chosen path replaces the placeholder, quoted,
    /// and the command runs in the terminal like any other.
    private func runWithChosenPath(_ command: String) {
        guard let placeholder = DoctorItem.placeholder(in: command) else {
            return runInTerminal(command)
        }
        let chosen: URL?
        if command.hasPrefix("jit vault export") {
            let save = NSSavePanel()
            save.title = "Export the vault"
            save.nameFieldStringValue = "jit-vault-\(Format.dateStamp()).export"
            save.canCreateDirectories = true
            chosen = save.runModal() == .OK ? save.url : nil
        } else {
            let open = NSOpenPanel()
            open.title = "Choose the \(placeholder.dropFirst().dropLast()) for: \(command)"
            open.canChooseFiles = true
            open.canChooseDirectories = true
            open.allowsMultipleSelection = false
            chosen = open.runModal() == .OK ? open.url : nil
        }
        guard let chosen else {
            return
        }
        runInTerminal(command.replacingOccurrences(of: placeholder, with: Terminal.quoted(chosen.path)))
    }

    /// The one destructive act the app performs itself, and it is a move
    /// to the Trash of a manifest that holds no secret. Confirmed first,
    /// named exactly, and followed by a recheck so the row disappears
    /// because doctor says so, not because the app assumed.
    private func confirmDeleteProfile(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "Delete the profile \u{201C}\(name)\u{201D}?"
        alert.informativeText = "Moves \(Format.home(ProfileStore.manifest(named: name).path)) to the Trash. "
            + "Anything that launched through this profile stops receiving its secrets. The vault is not changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        do {
            try ProfileStore.trashGlobal(named: name)
        } catch {
            let failed = NSAlert(error: error)
            failed.runModal()
        }
        runDoctor()
    }

    func openDoctor() {
        panel.dismiss()
        doctorWindow.present()
        if model.doctor == nil {
            runDoctor()
        }
    }

    /// How long a doctor result is trusted before a panel open rechecks.
    /// Doctor is prompt-free, but it reads the whole vault's envelopes and
    /// it blocks behind any vault command waiting in a terminal, so it is
    /// not something to run on every click.
    static let doctorTTL: TimeInterval = 300

    /// Rechecks only when the last result is older than doctorTTL. Explicit
    /// callers (Check Again, an action that changes state) use runDoctor.
    func refreshDoctorIfStale() {
        if let at = model.doctorAt, Date().timeIntervalSince(at) < Self.doctorTTL, model.doctor != nil {
            return
        }
        runDoctor()
    }

    /// One `jit doctor --format json`, off the main thread. The previous
    /// result stays on screen until this one lands.
    func runDoctor() {
        guard !model.doctorRunning else {
            return
        }
        model.doctorRunning = true
        Task.detached {
            let report = JitCLI.doctor()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                if let report {
                    model.doctor = report
                    model.doctorAt = Date()
                }
                model.doctorRunning = false
            }
        }
    }
}
