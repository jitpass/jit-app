// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The AI Agents window, in the order the website's "ai agents" page tells
/// it: the agents themselves (key, caches, reach), the files they read and
/// the grants that keep them working unattended, the copies they already
/// made, the MCP configs, and what none of this covers. Every fact is the
/// engine's; every button is one jit command after a sheet or dialog.
struct AgentsView: View {
    @ObservedObject var model: MenuModel
    let actions: AgentsActions

    private static let readsNote = "A migrated file (.env, ~/.aws/credentials) answers an agent with a decoy: "
        + "the value in the transcript is fake, and so is the one sent upstream. A grant keeps an agent's tools "
        + "working while you are away, for a window you choose."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
            reachLine.padding(.horizontal, 16).padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    agentsSection
                    readsSection
                    AgentsFindings(model: model, actions: actions)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .sheet(item: $model.agentsSheet) { sheet in
            switch sheet {
            case let .wrap(tool):
                if let record = model.toolListing?.tool(named: tool) {
                    WrapSheet(model: model, actions: ToolsActions(closeSheet: actions.closeSheet, wrap: actions.wrap), tool: record)
                }
            case let .result(title, text):
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            }
        }
        .onAppear(perform: actions.reload)
    }

    /// What none of this covers, on the scan button's tooltip.
    private static let limitsNote = "Scans the whole Mac. Not covered: a run you started sees real values; "
        + "a value typed only into a prompt has no file copy to match; a value already sent needs rotation."

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(summary).font(.headline)
            if model.toolsRefreshing {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Refresh", action: actions.reload).disabled(model.toolsRefreshing)
            Button("Scan Now", action: actions.scanNow).disabled(model.scanning)
                .help(Self.limitsNote)
        }
    }

    private var summary: String {
        guard let listing = model.toolListing else {
            return "AI Agents"
        }
        let agents = listing.agents
        if agents.isEmpty {
            return "No AI agent CLI installed here"
        }
        if let copies = model.macScan?.agentCopies.count, copies > 0 {
            return "\(copies) cop\(copies == 1 ? "y" : "ies") of your secrets in agent caches"
        }
        let protected = agents.filter { model.agentProtected($0) }.count
        return "\(protected) of \(agents.count) agent\(agents.count == 1 ? "" : "s") protected"
    }

    /// Consent is one machine-wide setting, so it is one line, not a line
    /// on every agent.
    private var reachLine: some View {
        HStack(spacing: 8) {
            Circle().fill(reachColor).frame(width: 7, height: 7)
            Text(reachText).font(.system(size: 12)).foregroundStyle(.secondary)
                .help("When an agent runs a tool that needs a machine credential (aws, git, docker…), "
                    + "JitPass asks you first. Settings › Service turns this off.")
            Spacer()
            if model.consentEnabled == false {
                Button("Settings…", action: actions.openSettings).controlSize(.small)
            }
        }
    }

    private var reachColor: Color {
        switch model.consentEnabled {
        case true: Color(StatusMark.green)
        case false: Color(StatusMark.amber)
        default: Color.secondary.opacity(0.5)
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        AgentsSection("Agents", "Two things per agent: where its own key sits, and whether its caches hold copies of your other secrets.") {
            if let listing = model.toolListing {
                if listing.agents.isEmpty {
                    Text("none installed").font(.system(size: 12)).foregroundStyle(.secondary)
                        .help("jit can wrap " + ToolRecord.agentTools.sorted().joined(separator: ", "))
                }
                ForEach(listing.agents) { agentRow($0) }
            } else {
                Text(model.toolsMessage ?? "Reading…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    /// One row per agent: the key and the caches as two aligned columns,
    /// the way the Tools window lays out its rows.
    private func agentRow(_ tool: ToolRecord) -> some View {
        HStack(spacing: 10) {
            Circle().fill(agentColor(tool)).frame(width: 7, height: 7)
            Text(tool.tool).fontWeight(.semibold).frame(width: 110, alignment: .leading)
            Text(tool.shortDoc).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).help(tool.doc ?? "")
            Spacer()
            column("key", keyText(tool))
            if let label = tool.agentLabel {
                column("caches", cachesText(label))
            }
            if model.toolsBusy == tool.tool {
                Text("Touch ID…").foregroundStyle(.secondary)
            } else {
                keyButton(tool)
                if let label = tool.agentLabel {
                    cachesButton(label)
                }
            }
        }
        .padding(.vertical, 2)
        .disabled(model.toolsBusy != nil)
    }

    private func column(_ label: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .frame(width: 150, alignment: .leading)
    }

    private func fact(_ label: String, _ text: String, @ViewBuilder button: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.system(size: 12, weight: .medium)).frame(width: 52, alignment: .trailing)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            button()
        }
    }

    /// Green when all three facts hold, red on cached copies, amber when
    /// the key is in a plaintext file or consent is off, grey otherwise.
    private func agentColor(_ tool: ToolRecord) -> Color {
        if let label = tool.agentLabel, let scan = model.macScan, scan.agentCopies(in: label) > 0 {
            return Color(StatusMark.red)
        }
        if model.agentProtected(tool) {
            return Color(StatusMark.green)
        }
        if tool.keyState(scan: model.macScan).needsAction || model.consentEnabled == false {
            return Color(StatusMark.amber)
        }
        return Color.secondary.opacity(0.5)
    }

    private func keyText(_ tool: ToolRecord) -> String {
        if tool.wrapped {
            return tool.isHealthy ? "wrapped" : tool.stateLabel
        }
        switch tool.keyState(scan: model.macScan) {
        case .protected: return "protected"
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"): return "in " + Format.home(source)
        case .found: return "in \(tool.tool)'s keychain"
        case .none: return "none found"
        case .unknown: return "not checked"
        }
    }

    @ViewBuilder private func keyButton(_ tool: ToolRecord) -> some View {
        if tool.wrapped {
            Button("Unwrap…") { actions.unwrap(tool.tool) }.controlSize(.small)
            if !tool.isHealthy {
                Button("Repair…") { actions.openSheet(.wrap(tool: tool.tool)) }.controlSize(.small)
            }
        } else if tool.keyState(scan: model.macScan).found || tool.keyState(scan: model.macScan) == .unknown {
            Button("Wrap…") { actions.openSheet(.wrap(tool: tool.tool)) }.controlSize(.small)
        } else {
            // Nothing to move: the sheet is still there for a key the user
            // has to paste, as a link rather than a button that nags.
            Button("add a key…") { actions.openSheet(.wrap(tool: tool.tool)) }.buttonStyle(.link).font(.system(size: 12))
        }
    }

    private func cachesText(_ label: String) -> String {
        guard let scan = model.macScan else {
            return "not scanned yet"
        }
        let copies = scan.agentCopies(in: label)
        return copies == 0 ? "clean" : "\(copies) cop\(copies == 1 ? "y" : "ies") of your secrets"
    }

    @ViewBuilder private func cachesButton(_ label: String) -> some View {
        if model.macScan == nil {
            Button("Scan Now", action: actions.scanNow).controlSize(.small).disabled(model.scanning)
        } else if model.macScan?.agentCopies(in: label) ?? 0 > 0 {
            Button("Clean Caches…", action: actions.cleanCaches).controlSize(.small)
        }
    }

    private var reachText: String {
        switch model.consentEnabled {
        case true: "asks you before a machine credential"
        case false: "consent off: machine credentials without asking"
        default: "service not running"
        }
    }

    // MARK: - What agents read, and grants

    private var readsSection: some View {
        AgentsSection("What agents read", Self.readsNote) {
            fact("Decoys", mountsText) {
                Button("Scan", action: actions.openScan).controlSize(.small)
            }
            fact("Grants", grantsText) {
                if !model.grants.isEmpty {
                    Button("Grants", action: actions.openGrants).controlSize(.small)
                }
                Button("New Grant…", action: actions.newGrant).controlSize(.small)
            }
        }
    }

    private var mountsText: String {
        guard let mounts = model.cli?.mounts else {
            return "not read yet"
        }
        if mounts.registered == 0 {
            return "none: protect a file in the scan window first"
        }
        return "\(mounts.registered) file\(mounts.registered == 1 ? "" : "s") serve decoys"
            + (mounts.servingReal ? " · real values inside a run" : "")
    }

    private var grantsText: String {
        if model.grants.isEmpty {
            return "none active"
        }
        let lines = model.grants.prefix(2).map { g in
            (g.name ?? g.anchor ?? "pid \(g.pid)") + " until " + Format.clock(g.expires)
        }
        return lines.joined(separator: " · ") + (model.grants.count > 2 ? " · …" : "")
    }
}

struct AgentsActions {
    var reload: () -> Void = {}
    var openSheet: (ToolsSheet) -> Void = { _ in }
    var closeSheet: () -> Void = {}
    var wrap: (String, String?) -> Void = { _, _ in }
    var unwrap: (String) -> Void = { _ in }
    var cleanCaches: () -> Void = {}
    var protectFile: (String) -> Void = { _ in }
    var scanNow: () -> Void = {}
    var newGrant: () -> Void = {}
    var openGrants: () -> Void = {}
    var openScan: () -> Void = {}
    var openSettings: () -> Void = {}
    var open: (String) -> Void = { _ in }
}
