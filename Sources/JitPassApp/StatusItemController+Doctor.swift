// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Which card or row an action belongs to: its busy line while it runs,
/// and its done or failed state after. A key alone (a Review sheet row)
/// keeps the old behaviour: busy until the recheck, a failure under the
/// header.
struct DoctorTarget {
    var key: String
    var card: DoctorCard?
    var button: DoctorButton?
    /// A row's own name for the outcome, instead of the card's.
    var subject: String?
}

/// One jit invocation an action runs in the app, with what it reads on
/// stdin. `closesAction` marks an action's last invocation, so a run of
/// several actions counts how many finished.
struct DoctorStep: Sendable {
    var argv: [String]
    var stdin: String?
    var closesAction = true
}

/// Doctor: the panel row and the findings window.
extension StatusItemController {
    var doctorActions: DoctorActions {
        DoctorActions(
            recheck: { [weak self] in
                self?.model.doctorMessage = nil
                self?.doctorProgress.outcome = nil
                self?.runDoctor()
            },
            copyReport: { [weak self] in self?.copyDoctorReport() },
            perform: { [weak self] action, row in self?.perform([action], target: DoctorTarget(key: row)) },
            run: { [weak self] button, card, key in self?.runBoardButton(button, card: card, key: key) },
            showAgain: { [weak self] button, key in
                if case let .unignore(command) = button.command {
                    self?.runIgnore([command], key: key)
                }
            },
            answer: { [weak self] yes in self?.answerConfirm(yes) },
            fit: { [weak self] height in self?.fitDoctorWindow(to: height) }
        )
    }

    /// The findings as text, for a ticket or a colleague: what Open in
    /// Terminal was really being asked for.
    func copyDoctorReport() {
        guard let report = model.doctor else {
            return
        }
        let board = DoctorBoard.make(report, offersVaultKeyMove: model.offersVaultKeyMove)
        let footer = Format.doctorSummary(report) + (model.doctorAt.map { " at " + Format.clock($0) } ?? "")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(board.reportText + "\n\n" + footer, forType: .string)
    }

    /// Whether an action may start: nothing else is running or rechecking.
    var doctorIdle: Bool {
        model.doctorBusy == nil && !model.doctorRunning
    }

    enum Prepared {
        case app([DoctorStep])
        case terminal(String)
    }

    /// Every panel an action needs once its question is answered: the
    /// file, the hidden value. Nil when the user cancelled either.
    func prepare(_ action: DoctorAction) -> Prepared? {
        guard let chosen = choosePath(for: action.needs) else {
            return nil
        }
        let (placeholder, path) = chosen
        guard let argv = action.argv else {
            let command = placeholder.map { action.command.replacingOccurrences(of: $0, with: Terminal.quoted(path)) }
            return .terminal(command ?? action.command)
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
            return nil
        }
        let filled = argv.map { arguments in
            arguments.map { placeholder != nil && $0 == placeholder ? path : $0 }
        }
        return .app(filled.enumerated().map { index, arguments in
            DoctorStep(argv: arguments, stdin: stdin, closesAction: index == filled.count - 1)
        })
    }

    /// Nil when the user cancelled; otherwise the placeholder (if any)
    /// and the path that replaces it ("" when nothing was needed).
    func choosePath(for needs: DoctorAction.Needs) -> (String?, String)? {
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

    /// Runs the steps off the main thread with the target marked busy,
    /// then rechecks so the card disappears because doctor says so. The
    /// first failure stops the run. A card shows how it ended (done, or
    /// what jit said); a row without a card shows a failure under the
    /// header. A failure shows jit's own output, and so does an action
    /// whose output is what was asked for; a destructive one that worked
    /// does not, because the card says how it ended and the window behind
    /// it already shows the new state.
    func applyInApp(_ steps: [DoctorStep], action: DoctorAction, target: DoctorTarget) {
        // A check that started while the dialogs were up is no reason to
        // drop what the user just confirmed: the recheck after this action
        // queues behind it. Another action cannot have started (the
        // dialogs were modal), but if one has, say so rather than vanish.
        guard model.doctorBusy == nil else {
            model.doctorMessage = "Another action is still running. Try again when it finishes."
            return
        }
        model.doctorBusy = target.key
        model.doctorMessage = nil
        doctorProgress.outcome = nil
        doctorProgress.presence = (target.button?.presence ?? false) || action.presence
        Task.detached {
            var failure: String?
            var output: [String] = []
            var completed = 0
            for step in steps {
                switch JitCLI.invoke(step.argv, stdin: step.stdin) {
                case let .success(outcome):
                    output.append(outcome.output)
                    if outcome.status != 0 {
                        let line = outcome.output.split(separator: "\n").last.map(String.init) ?? "exit \(outcome.status)"
                        failure = "jit \(step.argv.joined(separator: " ")): \(line)"
                    }
                case let .failure(error):
                    failure = "jit \(step.argv.joined(separator: " ")): \(Self.describe(error))"
                }
                if failure != nil {
                    break
                }
                if step.closesAction {
                    completed += 1
                }
            }
            let result = DoctorRunResult(failure: failure, output: output, completed: completed)
            await MainActor.run { [weak self] in
                self?.finishAction(result, action: action, target: target)
            }
        }
    }

    private func finishAction(_ result: DoctorRunResult, action: DoctorAction, target: DoctorTarget) {
        if action.presence {
            doctorWindow.reclaimFocus()
        }
        let text = result.output.filter { !$0.isEmpty }.joined(separator: "\n\n")
        if let card = target.card, let button = target.button {
            // Everything jit printed across the run, not just its last
            // line: the row's own box is where it is read now, and the
            // window that used to hold the rest does not open.
            let said = result.failure == nil || !text.isEmpty ? text : (result.failure ?? "")
            let outcome = card.outcome(
                key: target.key, button: button, completed: result.completed, output: said, failed: result.failure != nil,
                subject: target.subject
            )
            doctorProgress.outcome = outcome
            if outcome.state == .done {
                DispatchQueue.main.asyncAfter(deadline: .now() + DoctorOutcome.doneSeconds) { [weak self] in
                    self?.expireDoneOutcome(outcome)
                }
            }
        } else {
            model.doctorMessage = result.failure
        }
        runDoctor(afterAction: true)
        // A failure says so in the row that asked, with jit's own words
        // under it: there is no output window any more, and a black pane
        // over a window that already knows was never the answer. What
        // still opens is an action whose output IS the request (a
        // comparison, a service log), and it opens as a sheet in the
        // window's own type.
        if result.failure == nil, action.showsOutput {
            model.doctorSheet = .output(DoctorOutput(title: action.title, text: text))
        }
    }

    /// A done card stays doneSeconds, and until the recheck after it has
    /// landed, whichever is later: the card then goes because doctor no
    /// longer reports it.
    private func expireDoneOutcome(_ outcome: DoctorOutcome) {
        guard doctorProgress.outcome == outcome, model.doctorBusy == nil else {
            return
        }
        doctorProgress.outcome = nil
    }

    nonisolated static func describe(_ error: Error) -> String {
        if case let JitCLI.CLIError.failed(line) = error {
            return line.isEmpty ? "failed" : line
        }
        if case JitCLI.CLIError.notInstalled = error {
            return "jit is not installed"
        }
        return error.localizedDescription
    }

    /// The window asks to be the height of its findings.
    func fitDoctorWindow(to height: CGFloat) {
        doctorWindow.fit(to: height + DoctorView.chrome)
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
    /// the window can count them; the verdict still counts them once.
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
                self?.doctorLanded(report, afterAction: afterAction)
            }
        }
    }

    private func doctorLanded(_ report: DoctorReport?, afterAction: Bool) {
        model.doctorRunning = false
        if model.doctorRecheckPending {
            model.doctorRecheckPending = false
            runDoctor(afterAction: true)
            return
        }
        // Never leave a stale list looking current, least of all right
        // after an action that was meant to change it.
        model.doctorFailed = report == nil
        if let report {
            model.doctor = report
            model.doctorAt = Date()
        }
        // Only the check requested after an action ends its busy state:
        // one that started earlier (a panel refresh) may land while the
        // action is still running.
        if afterAction {
            model.doctorBusy = nil
            let shownLongEnough = doctorProgress.outcome.map { Date().timeIntervalSince($0.at) >= DoctorOutcome.doneSeconds }
            if doctorProgress.outcome?.state == .done, shownLongEnough == true {
                doctorProgress.outcome = nil
            }
        }
        vaultKeyDoctorLanded()
    }
}

/// What a run of steps left behind, handed from the worker to the main
/// thread in one piece.
struct DoctorRunResult: Sendable {
    var failure: String?
    var output: [String]
    var completed: Int
}
