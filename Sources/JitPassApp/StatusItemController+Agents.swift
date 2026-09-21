// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The AI Agents window's wiring. It reads the same tool listing, scan
/// and status the Tools window does, so nothing here runs a command of
/// its own: every action is one `jit` the CLI can also send, and the
/// window says what happened in its own banner rather than in a modal
/// over the state it just changed.
extension StatusItemController {
    /// The AI Agents window: the same listing, scan and status, laid out
    /// as the website's "ai agents" page tells it.
    func openAgents() {
        panel.dismiss()
        // The banner says what the last action did; opening the window
        // again is a new visit, not the moment after that action.
        model.agentsOutcome = nil
        model.toolsMessage = nil
        reloadTools()
        refreshDecoyReads() // the rows' "reads today", per agent
        agentsWindow.present()
    }

    var agentsActions: AgentsActions {
        AgentsActions(
            reload: { [weak self] in self?.reloadTools() },
            openSheet: { [weak self] sheet in
                self?.model.toolsMessage = nil
                self?.model.agentsSheet = sheet
            },
            closeSheet: { [weak self] in self?.model.agentsSheet = nil },
            scanNow: { [weak self] in
                // The digest reads Findings' scan, so the scan is started
                // where every scan is: in Findings, with its depth asked.
                self?.model.agentsOutcome = nil
                self?.openScan()
                self?.askDepth(scope: nil)
            },
            openGrants: { [weak self] in self?.openGrants() },
            openScan: { [weak self] in self?.openScan() },
            openSettings: { [weak self] in self?.openSettings() },
            openTools: { [weak self] in self?.openTools() },
            openAudit: { [weak self] in self?.openAudit() },
            fit: { [weak self] height in self?.agentsWindow.fit(to: height) }
        )
    }
}
