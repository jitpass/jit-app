// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Doctor actions confirmed from jit's own dry run: what the dialog says
/// is what jit reported a moment ago, and what runs is exactly the command
/// the dialog names.
extension StatusItemController {
    /// Delete All on the orphans: the dialog names what `jit vault orphans`
    /// lists now, not what a report up to doctorTTL old said. Prompt-free
    /// and quick, so it runs here, immediately before the dialog.
    func pruneOrphansFromDoctor(_ action: DoctorAction, target: DoctorTarget) {
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
        applyInApp([DoctorStep(argv: VaultOrphans.pruneArguments)], action: action, target: target)
    }

    /// Attach, Remove Profile, Migrate and Undo Migration: jit's dry run
    /// first, then one dialog worded from it, then exactly the command that
    /// dialog names (attach runs the profile names it listed; rm the one
    /// profile). Nothing runs when the dry run fails, which is what a jit
    /// older than 2.0 does: it has no `jit profile`. A plan with nothing to
    /// run (already attached, in use after all) rechecks, since the card it
    /// came from is out of date.
    func performPlanned(_ planned: DoctorAction.Planned, action: DoctorAction, target: DoctorTarget) {
        let answer: Result<DeleteConfirmation, Error>
        let unavailable: (String) -> DeleteConfirmation
        // The file the dialog is about, one click from Finder: the config
        // attaching records, the manifest removing deletes (vault
        // paths only, never a value).
        let reveal: RevealLink
        switch planned {
        case let .attach(config):
            reveal = RevealLink(title: "Show Config", path: config)
            answer = JitCLI.profileAttachPlan(config).map { $0.confirmation() }
            unavailable = {
                .profileUnavailable("Can't check what attaching would change", command: "jit profile attach", reason: $0)
            }
        case let .removeProfile(name, manifest):
            reveal = RevealLink(title: "Show Profile File", path: ProfileFiles.manifest(name, reported: manifest))
            answer = JitCLI.profileRmPlan(name).map { $0.confirmation() }
            unavailable = {
                .profileUnavailable("Can't check what removing \(name) deletes", command: "jit profile rm", reason: $0)
            }
        case let .migrate(targets):
            return performMigrate(.migrate, targets: targets, action: action, target: target)
        case let .undoMigration(targets):
            return performMigrate(.undo, targets: targets, action: action, target: target)
        }
        let confirmation: DeleteConfirmation = switch answer {
        case let .success(worded):
            worded
        case let .failure(error):
            unavailable(Self.describe(error))
        }
        guard Self.confirmDeletion(confirmation, reveal: reveal) else {
            if confirmation.button == nil, case .success = answer {
                runDoctor(afterAction: true)
            }
            return
        }
        applyInApp([DoctorStep(argv: confirmation.arguments)], action: action, target: target)
    }

    /// `jit migrate <file>` or `jit migrate undo <file>`, in the app. The
    /// file comes first when the user chooses it (Migrate a File…). The dry
    /// run can take a moment (a migrate by category scans the Mac), so it
    /// runs off the main thread with the card saying it is working; then
    /// the dialog shows jit's plan, and the button runs exactly
    /// `jit migrate --yes <file>` (or `undo --yes`). An undo writes
    /// plaintext back, so its button is red and not the default.
    func performMigrate(_ mode: MigratePlan.Mode, targets: [String], action: DoctorAction, target: DoctorTarget) {
        var targets = targets
        if case .existingPath = action.needs {
            guard let (placeholder, path) = choosePath(for: action.needs), let placeholder else {
                return
            }
            targets = targets.map { $0 == placeholder ? path : $0 }
        }
        guard model.doctorBusy == nil else {
            return
        }
        model.doctorBusy = target.key
        doctorProgress.presence = false
        doctorProgress.outcome = nil
        let chosen = targets
        Task.detached {
            let answer = JitCLI.migratePlan(mode, chosen)
            await MainActor.run { [weak self] in
                self?.model.doctorBusy = nil
                self?.confirmMigrate(answer, mode: mode, targets: chosen, action: action, target: target)
            }
        }
    }

    private func confirmMigrate(
        _ answer: Result<MigratePlan, Error>, mode: MigratePlan.Mode, targets: [String], action: DoctorAction, target: DoctorTarget
    ) {
        doctorWindow.reclaimFocus()
        let confirmation: DeleteConfirmation
        var plan: String?
        switch answer {
        case let .success(worded):
            confirmation = worded.confirmation()
            plan = worded.hasWork ? worded.text : nil
        case let .failure(error):
            confirmation = MigratePlan.unavailable(mode, targets: targets, reason: Self.describe(error))
        }
        let file = targets.first { $0.hasPrefix("/") }
        let reveal = file.map { RevealLink(title: "Show Config", path: $0) }
        guard DoctorDialogs.confirmPlan(confirmation, plan: plan, reveal: reveal) else {
            if confirmation.button == nil, case .success = answer {
                runDoctor(afterAction: true)
            }
            return
        }
        applyInApp([DoctorStep(argv: confirmation.arguments)], action: action, target: target)
    }

    // MARK: - Board buttons

    /// A card's button. Finder, the pasteboard and the terminal need no
    /// confirmation; a run of doctor actions goes through each action's
    /// own flow, and several (Set Values…) ask every value first, each in
    /// its own hidden field, and run only if none was cancelled.
    func runBoardButton(_ button: DoctorButton, card: DoctorCard, key: String) {
        switch button.command {
        case let .reveal(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case let .edit(path):
            Editor.open(path, line: nil)
        case let .copyPath(path):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        case let .terminal(command):
            runInTerminal(command)
        case .review:
            break
        case let .ignore(commands):
            if let line = card.ignoreConfirmation, !confirmIgnore(line) {
                return
            }
            runIgnore(commands, key: key)
        case let .unignore(command):
            runIgnore([command], key: key)
        case let .run(steps):
            let subject = key == card.id ? nil : card.rows.first { $0.id == key }?.text
            let target = DoctorTarget(key: key, card: card, button: button, subject: subject)
            if steps.count == 1, let action = steps.first {
                perform(action, target: target)
            } else {
                performSequence(steps, target: target)
            }
        }
    }

    /// Several actions as one fix: each one's dialogs in turn, then every
    /// command in order, stopping at the first that fails.
    private func performSequence(_ actions: [DoctorAction], target: DoctorTarget) {
        guard doctorIdle, let first = actions.first, !actions.contains(where: { $0.planned != nil }) else {
            return
        }
        var steps: [DoctorStep] = []
        for action in actions {
            guard case let .app(prepared)? = prepare(action) else {
                return
            }
            steps += prepared
        }
        applyInApp(steps, action: first, target: target)
    }

    // MARK: - Ignore

    /// A problem card's Ignore asks once, in one line: the tool still
    /// fails, Doctor only stops counting it. Advice is ignored unasked.
    private func confirmIgnore(_ line: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Ignore this problem?"
        alert.informativeText = line
        alert.addButton(withTitle: "Ignore")
        alert.addButton(withTitle: "Cancel")
        return alert.runFrontmost() == .alertFirstButtonReturn
    }

    /// `jit doctor ignore` (or `unignore`) for each finding, then a recheck,
    /// which moves the card to the ignored list or back. The card says it is
    /// working until the recheck lands; a failure shows under the header.
    func runIgnore(_ commands: [[String]], key: String) {
        guard doctorIdle, !commands.isEmpty else {
            return
        }
        model.doctorBusy = key
        model.doctorMessage = nil
        doctorProgress.presence = false
        doctorProgress.outcome = nil
        Task.detached {
            var failure: String?
            for arguments in commands {
                failure = Self.ignoreFailure(JitCLI.capture(arguments))
                if failure != nil {
                    break
                }
            }
            let said = failure.map { "jit \(commands[0].prefix(2).joined(separator: " ")): \($0)" }
            await MainActor.run { [weak self] in
                self?.model.doctorMessage = said
                self?.runDoctor(afterAction: true)
            }
        }
    }

    /// Why an ignore or unignore did not happen, from its JSON answer; nil
    /// when it did.
    private nonisolated static func ignoreFailure(_ answer: Result<JitCLI.Captured, Error>) -> String? {
        switch answer {
        case let .success(captured):
            let result = try? DoctorIgnoreResult.parse(captured.stdout)
            if let error = result?.error {
                return error
            }
            guard captured.status == 0 else {
                let said = captured.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return said.isEmpty ? "exit \(captured.status)" : said
            }
            return result == nil ? "no answer (is this jit older than 2.1?)" : nil
        case let .failure(error):
            return describe(error)
        }
    }
}
