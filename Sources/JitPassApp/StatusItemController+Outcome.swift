// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Where an action's result, or its failure, is said: the window in front.
extension StatusItemController {
    /// The result goes to whichever window is in front. Findings and AI
    /// Agents have a banner region, so there it is a sentence in the
    /// window with jit's own words one click away, and not a modal on top
    /// of the state it just changed.
    func showResult(title: String, text: String, failed: Bool = false, undo: [String] = [], changes: ChangeSheet? = nil) {
        let outcome = WindowOutcome(title: title, text: text, failed: failed, undo: undo, changes: changes)
        if scanWindow.isKeyWindow {
            model.findingsOutcome = outcome
        } else if decoysWindow.isKeyWindow {
            model.decoysOutcome = outcome
        } else if agentsWindow.isKeyWindow || (agentsWindow.isVisible && !toolsWindow.isVisible) {
            model.agentsOutcome = outcome
        } else {
            model.toolsSheet = ToolsSheet.result(title: title, text: text)
        }
    }

    /// A failed run, said where `showResult` would have put its success.
    /// Tools and AI Agents show `toolsMessage` already; Findings and Decoys
    /// only their banner, so there the verb and jit's line become one. No
    /// window in front — the redact after a scheduled scan — is Findings,
    /// the window that owns the schedule.
    func showFailure(_ verb: String, line: String) {
        let outcome = WindowOutcome(title: ScanWording.actionFailed(verb, line: line), text: "", failed: true)
        if decoysWindow.isKeyWindow {
            model.decoysOutcome = outcome
        } else if !(agentsWindow.isKeyWindow || toolsWindow.isKeyWindow) {
            model.findingsOutcome = outcome
        }
    }
}
