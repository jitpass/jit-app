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

    /// Runs a doctor action. In the app when it carries `argv`: any path it
    /// needs is chosen first (a save panel for a file to create, an open
    /// panel for one that exists), any value or passphrase asked for in a
    /// hidden field, then the commands run one after the other off the
    /// main thread and doctor rechecks. In the terminal otherwise: a
    /// migrate wants its plan read, `sudo` and `brew` want a shell. A
    /// destructive one is confirmed here first, naming the command.
    private func perform(_ action: DoctorAction) {
        if action.destructive, !confirmDestructive(action) {
            return
        }
        guard let chosen = choosePath(for: action.needs) else {
            return
        }
        let (placeholder, path) = chosen
        guard let argv = action.argv else {
            let command = placeholder.map { action.command.replacingOccurrences(of: $0, with: Terminal.quoted(path)) }
            return runInTerminal(command ?? action.command)
        }
        var stdin: String?
        switch action.input {
        case let .secret(prompt):
            stdin = DoctorDialogs.askSecret(prompt, title: action.title)
        case let .passphrase(prompt):
            stdin = DoctorDialogs.askPassphrase(prompt, title: action.title)
        case nil:
            break
        }
        if action.input != nil, stdin == nil {
            return
        }
        let filled = argv.map { arguments in
            arguments.map { placeholder != nil && $0 == placeholder ? path : $0 }
        }
        applyInApp(filled, stdin: stdin, title: action.showsOutput ? action.title : nil)
    }

    /// Nil when the user cancelled; otherwise the placeholder (if any)
    /// and the path that replaces it ("" when nothing was needed).
    private func choosePath(for needs: DoctorAction.Needs) -> (String?, String)? {
        switch needs {
        case .nothing:
            return (nil, "")
        case let .existingPath(placeholder):
            let open = NSOpenPanel()
            open.title = "Choose the \(placeholder.dropFirst().dropLast())"
            open.canChooseFiles = true
            open.canChooseDirectories = true
            open.allowsMultipleSelection = false
            guard open.runModal() == .OK, let url = open.url else {
                return nil
            }
            return (placeholder, url.path)
        case let .newFile(placeholder):
            let save = NSSavePanel()
            save.title = "Export the vault"
            save.nameFieldStringValue = "jit-vault-\(Format.dateStamp()).export"
            save.canCreateDirectories = true
            guard save.runModal() == .OK, let url = save.url else {
                return nil
            }
            return (placeholder, url.path)
        }
    }

    /// Runs the commands off the main thread, then rechecks so the rows
    /// disappear because doctor says so. The first failure stops the run
    /// and is shown under the header; with `title`, the output is shown.
    private func applyInApp(_ argv: [[String]], stdin: String?, title: String?) {
        guard !model.doctorRunning else {
            return
        }
        model.doctorRunning = true
        model.doctorMessage = nil
        Task.detached {
            var failure: String?
            var output: [String] = []
            for arguments in argv {
                switch JitCLI.execute(arguments, stdin: stdin) {
                case let .success(text):
                    output.append(text)
                case let .failure(error):
                    failure = "jit \(arguments.joined(separator: " ")): \(Self.describe(error))"
                }
                if failure != nil {
                    break
                }
            }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.doctorRunning = false
                model.doctorMessage = failure
                if let title, failure == nil {
                    DoctorDialogs.showOutput(output.joined(separator: "\n\n"), title: title)
                }
                runDoctor()
            }
        }
    }

    private nonisolated static func describe(_ error: Error) -> String {
        if case let JitCLI.CLIError.failed(line) = error {
            return line.isEmpty ? "failed" : line
        }
        return error.localizedDescription
    }

    private func confirmDestructive(_ action: DoctorAction) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(action.title)?"
        // In-app commands carry --yes, so this dialog is the only question;
        // a terminal one still gets jit's own confirmation.
        alert.informativeText = action.argv == nil
            ? "This opens the terminal and runs:\n\n\(action.command)\n\nIt deletes something for good. jit asks once more before it does."
            : "This runs:\n\n\(action.command)\n\nIt deletes something for good, and nothing asks again."
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
