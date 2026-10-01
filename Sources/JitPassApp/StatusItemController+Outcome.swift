// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Where an action's result, or its failure, is said: the window it was
/// asked from.
extension StatusItemController {
    /// The window in front now, by `OutcomeWindow.front`'s rule.
    var frontOutcomeWindow: OutcomeWindow {
        OutcomeWindow.front(
            findingsKey: scanWindow.isKeyWindow,
            decoysKey: decoysWindow.isKeyWindow,
            agentsKey: agentsWindow.isKeyWindow,
            agentsVisible: agentsWindow.isVisible,
            toolsVisible: toolsWindow.isVisible
        )
    }

    /// The result goes to the window its action was asked from while a
    /// tools action lands (`outcomeWindowOverride`), else to whichever
    /// window is in front. Findings and AI
    /// Agents have a banner region, so there it is a sentence in the
    /// window with jit's own words one click away, and not a modal on top
    /// of the state it just changed.
    func showResult(title: String, text: String, failed: Bool = false, undo: [String] = [], changes: ChangeSheet) {
        let outcome = WindowOutcome(title: title, text: text, failed: failed, undo: undo, changes: changes)
        // Inside a tools action's landing, the window it was asked from
        // (runTools); otherwise the window in front.
        switch outcomeWindowOverride ?? frontOutcomeWindow {
        case .findings: model.findingsOutcome = outcome
        case .decoys: model.decoysOutcome = outcome
        case .agents: model.agentsOutcome = outcome
        case .tools: model.toolsSheet = .changes(changes)
        }
    }

    /// A result as rows, in the window it was asked from.
    func showChanges(_ sheet: ChangeSheet) {
        showResult(title: sheet.title, text: sheet.report, failed: sheet.failed, undo: sheet.undo, changes: sheet)
    }

    /// A failed run, said in the window the action came from. `toolsMessage`
    /// is already set, and AI Agents and Tools show it; Findings and Decoys
    /// show only their banner, so there the verb and jit's line become one.
    func showFailure(_ verb: String, line: String, in window: OutcomeWindow) {
        guard window.needsFailureBanner else {
            return
        }
        let outcome = WindowOutcome(title: ScanWording.actionFailed(verb, line: line), text: "", failed: true)
        if window == .findings {
            model.findingsOutcome = outcome
        } else {
            model.decoysOutcome = outcome
        }
    }
}
