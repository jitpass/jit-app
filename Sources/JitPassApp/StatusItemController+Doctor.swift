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
            perform: { [weak self] action in self?.perform(action) },
            deleteProfile: { [weak self] name in self?.confirmDeleteProfile(name) }
        )
    }

    /// Runs a doctor action in the terminal. One that names a `<file>` or
    /// `<path>` gets a panel first: a save panel for a file to CREATE (an
    /// export), an open panel for something that exists. The chosen path
    /// replaces every placeholder, quoted. A destructive one is confirmed
    /// here as well, naming the command, because jit's own y/N comes only
    /// after the terminal has already opened.
    private func perform(_ action: DoctorAction) {
        if action.destructive, !confirmDestructive(action) {
            return
        }
        if let argv = action.argv {
            return applyInApp(argv)
        }
        switch action.needs {
        case .nothing:
            runInTerminal(action.command)
        case let .existingPath(placeholder):
            let open = NSOpenPanel()
            open.title = "Choose the \(placeholder.dropFirst().dropLast()) for: \(action.command)"
            open.canChooseFiles = true
            open.canChooseDirectories = true
            open.allowsMultipleSelection = false
            guard open.runModal() == .OK, let url = open.url else {
                return
            }
            runInTerminal(action.command.replacingOccurrences(of: placeholder, with: Terminal.quoted(url.path)))
        case let .newFile(placeholder):
            let save = NSSavePanel()
            save.title = "Export the vault"
            save.nameFieldStringValue = "jit-vault-\(Format.dateStamp()).export"
            save.canCreateDirectories = true
            guard save.runModal() == .OK, let url = save.url else {
                return
            }
            runInTerminal(action.command.replacingOccurrences(of: placeholder, with: Terminal.quoted(url.path)))
        }
    }

    /// Runs prompt-free jit commands off the main thread, then rechecks so
    /// the rows disappear because doctor says so. The first failure stops
    /// the run and is shown under the header.
    private func applyInApp(_ argv: [[String]]) {
        guard !model.doctorRunning else {
            return
        }
        model.doctorRunning = true
        model.doctorMessage = nil
        Task.detached {
            var failure: String?
            for arguments in argv {
                if case let .failure(error) = JitCLI.apply(arguments) {
                    failure = "jit \(arguments.joined(separator: " ")): \(error.localizedDescription)"
                    break
                }
            }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.doctorRunning = false
                model.doctorMessage = failure
                runDoctor()
            }
        }
    }

    private func confirmDestructive(_ action: DoctorAction) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(action.title)?"
        alert.informativeText = "This opens the terminal and runs:\n\n\(action.command)\n\n"
            + "It deletes something for good. jit asks once more before it does."
        alert.alertStyle = .warning
        alert.addButton(withTitle: action.title)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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

    /// One `jit doctor --format json --orphans`, off the main thread. The
    /// previous result stays on screen until this one lands. --orphans so
    /// the window can list them; the verdict still counts them once.
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
