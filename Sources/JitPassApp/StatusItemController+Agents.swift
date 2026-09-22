// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The AI Agents window's wiring. It reads the same tool listing, scan
/// and status the Tools window does, and the audit for the week; its two
/// verbs are Findings' own Clean Caches and Redact, so nothing here runs a
/// command the CLI cannot, and the window says what happened in its
/// banner rather than in a modal over the state it just changed.
extension StatusItemController {
    func openAgents() {
        panel.dismiss()
        // The banner says what the last action did; opening the window
        // again is a new visit, not the moment after that action.
        model.agentsOutcome = nil
        model.toolsMessage = nil
        reloadTools()
        refreshAgentActivity()
        agentsWindow.present()
    }

    /// `jit audit --since 7d`, prompt-free, off the main thread: what each
    /// agent launched and what its processes were served, for the cards'
    /// "This week" row and their note.
    func refreshAgentActivity() {
        let filter = AuditFilter(since: "7d", limit: 0)
        Task.detached {
            let report = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                guard let self, let report else {
                    return
                }
                let full = report.addingLive(liveServes, filter: filter)
                var activity: [String: AgentActivity] = [:]
                for agent in model.toolListing?.agents ?? [] {
                    activity[agent.tool] = full.agentActivity(tool: agent.tool)
                }
                model.agentActivity = activity
            }
        }
    }

    var agentsActions: AgentsActions {
        AgentsActions(
            reload: { [weak self] in
                self?.reloadTools()
                self?.refreshAgentActivity()
            },
            openSheet: { [weak self] sheet in
                self?.model.toolsMessage = nil
                self?.model.agentsSheet = sheet
            },
            closeSheet: { [weak self] in self?.model.agentsSheet = nil },
            cleanCaches: { [weak self] in self?.cleanCaches() },
            redact: { [weak self] agent in self?.redactAgent(agent) },
            setRedactAfterScan: { [weak self] agent, on in self?.setRedactAfterScan(agent: agent, on: on) },
            openGrants: { [weak self] in self?.openGrants() },
            openScan: { [weak self] in self?.openScan() },
            openSettings: { [weak self] in self?.openSettings() },
            openTools: { [weak self] in self?.openTools() },
            openAudit: { [weak self] agent in
                self?.openAudit(filter: agent.map { AuditFilter(parent: $0.tool, since: "7d") })
            },
            fit: { [weak self] height in self?.agentsWindow.fit(to: height) }
        )
    }

    /// Findings' Redact, narrowed to the files the scan placed in this
    /// agent's caches: the same dialog, the same one-way marker.
    func redactAgent(_ agent: ToolRecord) {
        guard let label = agent.agentLabel, let scan = model.macScan else {
            return
        }
        let exposure = scan.agentExposure(label)
        guard !exposure.tokenPaths.isEmpty else {
            return
        }
        let what = "\(exposure.tokens) token" + (exposure.tokens == 1 ? "" : "s") + " in " + label + "'s files"
        redact(files: exposure.tokenPaths, lines: [], what: what, place: nil)
    }

    /// The agent's own setting: its caches are redacted after every
    /// scheduled scan, without a dialog. The global switch in Settings
    /// covers every agent and reads as on here.
    func setRedactAfterScan(agent: ToolRecord, on: Bool) {
        if on {
            model.redactAgents.insert(agent.tool)
        } else {
            model.redactAgents.remove(agent.tool)
        }
        UserDefaults.standard.set(Array(model.redactAgents).sorted(), forKey: Notifier.redactAgentsKey)
    }
}
