// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The panel's rows, each a PanelValue: the number and the dot come from
/// the same facts the row's window shows, so the panel is the windows'
/// marks in a column. The panel counts; the window names.
extension MenuModel {
    var vaultRow: PanelValue.Row? {
        if let listing = vaultListing {
            return PanelValue.vault(secrets: listing.secrets.count)
        }
        return cli?.vault.map { PanelValue.vault(secrets: $0.secretsStored) }
    }

    var agentsRow: PanelValue.Row? {
        let cards = agentCards
        guard !cards.isEmpty else {
            return nil
        }
        let copies = cards.reduce(0) { $0 + (macScan?.agentExposure($1.tool.agentLabel ?? $1.tool.tool).total ?? 0) }
        return PanelValue.agents(copies: copies, needing: cards.filter { $0.card.state == .amber }.count, scanned: macScan != nil)
    }

    var toolsRow: PanelValue.Row? {
        guard let listing = toolListing else {
            return nil
        }
        let tools = listing.others
        return PanelValue.tools(
            broken: tools.filter { $0.wrapped && !$0.isHealthy }.count,
            expired: (cli?.sessions ?? []).filter { !$0.live }.count,
            toProtect: toolsWithKeyInTheOpen.filter { !$0.isAgent }.count,
            wrapped: tools.filter { $0.wrapped || $0.isProtected }.count
        )
    }

    var serviceRow: PanelValue.Row {
        if case .notRunning = state {
            return PanelValue.service(running: false)
        }
        return PanelValue.service(running: true)
    }

    var grantsRow: PanelValue.Row {
        PanelValue.grants(active: grants.count)
    }

    var jobsBoard: JobsBoard {
        JobsBoard(jobs: jobs, proposals: jobProposals)
    }

    /// Nil, so no row, until AI Jobs is used: a job, a proposal, or Claude
    /// Desktop connected.
    var jobsRow: PanelValue.Row? {
        PanelValue.aiJobs(jobsBoard, connected: mcpStatus.values.contains(where: \.isConnected))
    }

    var claudeDesktopMCP: MCPStatus? {
        mcpStatus[MCPApp.claudeDesktop.id]
    }

    var claudeDesktopInstalled: Bool {
        installedApps.contains(MCPApp.claudeDesktop.id)
    }

    /// The AI apps installed here that jit can connect, in a stable order.
    var connectableApps: [MCPApp] {
        MCPApp.allCases.filter { installedApps.contains($0.id) }
    }

    /// The Decoys window's own report, from what the panel already holds:
    /// the mount list, the vault's names, the week's serve events.
    var decoyReport: DecoyReport {
        DecoyReport.make(
            mounts: cli?.protectedFiles ?? [],
            secrets: vaultListing?.secrets ?? [],
            events: decoyEvents,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    var decoysRow: PanelValue.Row? {
        let files = cli?.mounts?.registered ?? cli?.protectedFiles.count ?? 0
        return PanelValue.decoys(files: files, broken: decoyReport.broken.count, readsToday: decoyReads24h ?? 0)
    }

    var doctorRow: PanelValue.Row {
        PanelValue.doctor(
            problems: doctor?.problems.count ?? 0, warnings: doctor?.warningCount ?? 0,
            checked: doctor != nil, checking: doctorRunning
        )
    }

    var findingsRow: PanelValue.Row {
        guard let report = macScan else {
            return PanelValue.findings(todos: 0, worst: .none, scanned: false, scanning: scanning)
        }
        let todos = report.todos(deepAvailable: false).filter {
            if case .show = $0.action {
                true
            } else {
                false
            }
        }
        let tiers = report.tiersPresent.filter { $0 != .testFixtures }
        let worst: PanelValue.Tone = tiers.isEmpty ? .none : tiers.contains { $0 != .protect } ? .red : .amber
        return PanelValue.findings(todos: todos.count, worst: worst, scanned: true, scanning: scanning)
    }

    /// The Doctor's sentence, for the places that still read it.
    var doctorValue: String {
        doctorRow.text
    }
}
