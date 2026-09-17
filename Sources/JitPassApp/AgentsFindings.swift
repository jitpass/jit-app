// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// A section of the AI Agents window: a small-caps title, its note as a
/// tooltip, and the rows in an inset card so the sections read as
/// separate things rather than one column of text.
struct AgentsSection<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, _ note: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.note = note
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .help(note).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// The scan-backed half of the AI Agents window: the copies agents already
/// made, and the MCP configs. Both read the last whole-Mac scan.
struct AgentsFindings: View {
    @ObservedObject var model: MenuModel
    let actions: AgentsActions

    var body: some View {
        cachesSection
        mcpSection
    }

    // MARK: - Caches

    private static let cachesNote = "Agents keep snapshots of every file they edit, pasted text, the shell environment "
        + "and the conversation. The scan looks in them for the exact credentials it confirmed in your real files."

    private static let mcpNote = "Tokens in .mcp.json, mcp.json, Claude Desktop's config and Claude Code's ~/.claude.json. "
        + "Every key in an env block is a finding; Protect moves it into the vault."

    var cachesSection: some View {
        AgentsSection("Cached copies", Self.cachesNote) {
            if let scan = model.macScan {
                let groups = scan.agentCacheGroups
                if groups.isEmpty {
                    Text("none found").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(groups) { g in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Severity.color(g.severity)).frame(width: 7, height: 7)
                        Text(g.agent + " · " + g.area).font(.system(size: 12, weight: .medium))
                        Text(cacheDetail(g)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                    }
                }
                if !groups.isEmpty {
                    Button("Clean Caches…", action: actions.cleanCaches).controlSize(.small).disabled(model.toolsBusy != nil)
                }
            } else {
                Text("not scanned yet").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func cacheDetail(_ g: ScanAgentGroup) -> String {
        let copies = g.findings.count
        let files = g.files.count
        var text = "\(copies) cop\(copies == 1 ? "y" : "ies") in \(files) file\(files == 1 ? "" : "s")"
        let origins = g.origins.map(Format.home)
        if !origins.isEmpty {
            text += ", from " + origins.prefix(2).joined(separator: ", ") + (origins.count > 2 ? ", …" : "")
        }
        return text
    }

    // MARK: - MCP

    var mcpSection: some View {
        AgentsSection("MCP servers", Self.mcpNote) {
            if let scan = model.macScan {
                let groups = scan.mcpByFile
                if groups.isEmpty {
                    Text("none found").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(groups) { g in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Severity.color(g.severity)).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.home(g.filePath)).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                .truncationMode(.head)
                            ForEach(g.findings) { f in
                                Text((f.keyName ?? "") + (f.migratable ? "" : " · reported, not moved"))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).help(f.evidence)
                            }
                        }
                        Spacer()
                        Button("Open") { actions.open(g.filePath) }.buttonStyle(.link).font(.system(size: 12))
                        if g.findings.contains(where: \.migratable) {
                            Button("Protect…") { actions.protectFile(g.filePath) }.controlSize(.small).disabled(model.toolsBusy != nil)
                        }
                    }
                }
            } else {
                Text("not scanned yet").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
