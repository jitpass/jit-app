// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// A press being prepared: the actions it still has to ask about, the
/// invocations already prepared, and where the answer goes. It exists
/// because the one question is a sheet now, not a modal alert: asking no
/// longer blocks in the middle of a function, so what was a loop is a
/// walk that stops at each question and resumes on the answer.
struct DoctorPending {
    var remaining: [DoctorAction]
    var steps: [DoctorStep] = []
    var target: DoctorTarget
    /// The press's first action, which names the run in its outcome.
    var action: DoctorAction
    /// The action at the head has been answered yes.
    var confirmed = false
}

/// Doctor's one question, and the press waiting on it.
///
/// The question is a sheet on the window now, not a modal alert, so asking
/// no longer blocks in the middle of a function: what was a loop over a
/// press's actions is a walk that stops at each question and resumes on
/// the answer.
extension StatusItemController {
    /// Runs a press's actions for `target`. Refused up front while another
    /// action or a check is running, so a second click never walks through
    /// a question and a panel only to do nothing. In the app when they
    /// carry `argv`: the destructive one's question first, then any path
    /// it needs (a save panel for a file to create, an open panel for one
    /// that exists), any value or passphrase in a hidden field, then the
    /// commands run one after the other off the main thread and doctor
    /// rechecks. In the terminal otherwise: `sudo` wants a password, a
    /// tool log-in wants a browser and a code.
    func perform(_ actions: [DoctorAction], target: DoctorTarget) {
        guard doctorIdle, let first = actions.first else {
            return
        }
        if actions.count == 1, let planned = first.planned {
            return performPlanned(planned, action: first, target: target)
        }
        guard !actions.contains(where: { $0.planned != nil }) else {
            return
        }
        doctorPending = DoctorPending(remaining: actions, target: target, action: first)
        continuePending()
    }

    /// Walks the press: each action's question first (a sheet, which comes
    /// back through `answerConfirm`), then its panels and hidden fields,
    /// then the next one. Runs everything once the last is ready.
    func continuePending() {
        guard var pending = doctorPending else {
            return
        }
        while let action = pending.remaining.first {
            if action.destructive, !pending.confirmed {
                doctorPending = pending
                model.doctorSheet = .confirm(DoctorConfirmRequest(
                    confirmation: DoctorAdvice.confirm(action), fact: rowFact(pending.target)
                ))
                return
            }
            pending.remaining.removeFirst()
            pending.confirmed = false
            switch prepare(action) {
            case nil:
                doctorPending = nil
                return
            case let .terminal(command):
                doctorPending = nil
                return runInTerminal(command)
            case let .app(steps):
                pending.steps += steps
            }
        }
        doctorPending = nil
        applyInApp(pending.steps, action: pending.action, target: pending.target)
    }

    /// The sheet's answer. No is the end of the press: nothing ran, and
    /// nothing is left waiting.
    func answerConfirm(_ yes: Bool) {
        model.doctorSheet = nil
        guard var pending = doctorPending, yes else {
            doctorPending = nil
            return
        }
        pending.confirmed = true
        doctorPending = pending
        continuePending()
    }

    /// What the row said about the file, so the sheet and the row it came
    /// from give the same reason.
    private func rowFact(_ target: DoctorTarget) -> String? {
        target.card?.rows.first { $0.id == target.key }?.fact
    }
}
