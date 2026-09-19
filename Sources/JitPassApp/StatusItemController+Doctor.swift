// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Doctor: the panel row and the findings window.
extension StatusItemController {
    var doctorActions: DoctorActions {
        DoctorActions(
            recheck: { [weak self] in
                self?.model.doctorMessage = nil
                self?.runDoctor()
            },
            openInTerminal: { [weak self] in self?.runInTerminal("jit doctor") },
            perform: { [weak self] action, row in self?.perform(action, row: row) }
        )
    }

    /// Whether an action may start: nothing else is running or rechecking.
    private var doctorIdle: Bool {
        model.doctorBusy == nil && !model.doctorRunning
    }

    /// Runs a doctor action for `row`. Refused up front while another
    /// action or a check is running, so a second click never walks through
    /// a confirmation and a panel only to do nothing. In the app when it
    /// carries `argv`: any path it needs is chosen first (a save panel for
    /// a file to create, an open panel for one that exists), any value or
    /// passphrase asked for in a hidden field, then the commands run one
    /// after the other off the main thread and doctor rechecks. In the
    /// terminal otherwise: a migrate wants its plan read, an unmount its
    /// own y/N, `sudo` a password. A destructive one is confirmed here
    /// first, naming the command.
    private func perform(_ action: DoctorAction, row: String) {
        guard doctorIdle else {
            return
        }
        if action.argv == [VaultOrphans.pruneArguments] {
            return pruneOrphansFromDoctor(action, row: row)
        }
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
        applyInApp(filled, stdin: stdin, action: action, row: row)
    }

    /// Delete All on the orphans: the dialog names what `jit vault orphans`
    /// lists now, not what a report up to doctorTTL old said. Prompt-free
    /// and quick, so it runs here, immediately before the dialog.
    private func pruneOrphansFromDoctor(_ action: DoctorAction, row: String) {
        let fresh: VaultOrphans
        do {
            fresh = try JitCLI.vaultOrphans()
        } catch {
            model.doctorMessage = "jit vault orphans: \(Self.describe(error))"
            return
        }
        let confirmation = fresh.pruneConfirmation()
        guard Self.confirmDeletion(confirmation) else {
            if confirmation.button == nil {
                runDoctor(afterAction: true)
            }
            return
        }
        applyInApp([VaultOrphans.pruneArguments], stdin: nil, action: action, row: row)
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
            guard open.runFrontmost() == .OK, let url = open.url else {
                return nil
            }
            return (placeholder, url.path)
        case let .newFile(placeholder):
            let save = NSSavePanel()
            save.title = "Export the vault"
            save.nameFieldStringValue = "jit-vault-\(Format.dateStamp()).export"
            save.canCreateDirectories = true
            guard save.runFrontmost() == .OK, let url = save.url else {
                return nil
            }
            return (placeholder, url.path)
        }
    }

    /// Runs the commands off the main thread with `row` marked busy, then
    /// rechecks so the rows disappear because doctor says so; the row stays
    /// busy until that recheck lands. The first failure stops the run and
    /// is shown under the header. The output is shown when it is what the
    /// user asked for, and for a destructive action either way, so what was
    /// deleted, or why nothing was, is on screen and not only in a log.
    private func applyInApp(_ argv: [[String]], stdin: String?, action: DoctorAction, row: String) {
        // A check that started while the dialogs were up is no reason to
        // drop what the user just confirmed: the recheck after this action
        // queues behind it. Another action cannot have started (the
        // dialogs were modal), but if one has, say so rather than vanish.
        guard model.doctorBusy == nil else {
            model.doctorMessage = "Another action is still running. Try again when it finishes."
            return
        }
        model.doctorBusy = row
        model.doctorMessage = nil
        Task.detached {
            var failure: String?
            var output: [String] = []
            for arguments in argv {
                switch JitCLI.invoke(arguments, stdin: stdin) {
                case let .success(outcome):
                    output.append(outcome.output)
                    if outcome.status != 0 {
                        let line = outcome.output.split(separator: "\n").last.map(String.init) ?? "exit \(outcome.status)"
                        failure = "jit \(arguments.joined(separator: " ")): \(line)"
                    }
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
                model.doctorMessage = failure
                runDoctor(afterAction: true)
                let text = output.filter { !$0.isEmpty }.joined(separator: "\n\n")
                if let failure, action.destructive {
                    DoctorDialogs.showOutput(text.isEmpty ? failure : text, title: "\(action.title) failed")
                } else if failure == nil, action.destructive || action.showsOutput {
                    DoctorDialogs.showOutput(text, title: action.title)
                }
            }
        }
    }

    private nonisolated static func describe(_ error: Error) -> String {
        if case let JitCLI.CLIError.failed(line) = error {
            return line.isEmpty ? "failed" : line
        }
        if case JitCLI.CLIError.notInstalled = error {
            return "jit is not installed"
        }
        return error.localizedDescription
    }

    private func confirmDestructive(_ action: DoctorAction) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(action.title)?"
        alert.informativeText = DoctorAdvice.confirmation(for: action)
        alert.alertStyle = .warning
        alert.addButton(withTitle: action.title)
        alert.addButton(withTitle: "Cancel")
        return alert.runFrontmost() == .alertFirstButtonReturn
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
    /// `afterAction`: an action just changed state, so a check already
    /// running (which started before it) is followed by another rather
    /// than trusted, and the busy row clears only when a fresh one lands.
    func runDoctor(afterAction: Bool = false) {
        guard !model.doctorRunning else {
            if afterAction {
                model.doctorRecheckPending = true
            }
            return
        }
        model.doctorRunning = true
        Task.detached {
            let report = JitCLI.doctor()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.doctorRunning = false
                if model.doctorRecheckPending {
                    model.doctorRecheckPending = false
                    runDoctor(afterAction: true)
                    return
                }
                // Never leave a stale list looking current, least of all
                // right after an action that was meant to change it.
                model.doctorFailed = report == nil
                if let report {
                    model.doctor = report
                    model.doctorAt = Date()
                }
                // Only the check requested after an action ends its busy
                // state: one that started earlier (a panel refresh) may land
                // while the action is still running.
                if afterAction {
                    model.doctorBusy = nil
                }
            }
        }
    }
}
