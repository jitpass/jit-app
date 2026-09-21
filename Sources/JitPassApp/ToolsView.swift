// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The tools jit knows on this Mac, in two sections: the AI coding agents
/// first, then everything else. Every state word is `jit wrap list`'s own
/// verdict; the bar under the list shows the selected tool's facts and the
/// commands that change them, which in phase 1 all run in the terminal.
struct ToolsView: View {
    @ObservedObject var model: MenuModel
    let actions: ToolsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            if let message = model.toolsMessage, model.toolListing == nil {
                Text(message).foregroundStyle(Color(StatusMark.red)).padding(.horizontal, 16).padding(.bottom, 8)
            }
            if let listing = model.toolListing {
                if listing.others.isEmpty {
                    Spacer()
                    Text("None of the tools jit can wrap is installed on this Mac.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    list(listing)
                }
            } else {
                Spacer()
                Text("Reading…").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
            Divider()
            selectionBar
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .sheet(item: $model.toolsSheet) { sheet in
            switch sheet {
            case let .wrap(tool):
                if let record = model.toolListing?.tool(named: tool) {
                    WrapSheet(model: model, actions: actions, tool: record)
                }
            case .handWrap:
                HandWrapSheet(model: model, actions: actions)
            case let .result(title, text):
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            case .scanDepth:
                // The Findings window's question; never opened from here.
                EmptyView()
            }
        }
        .onAppear(perform: actions.reload)
        .onChange(of: model.toolListing) { _, _ in keepSelectionValid() }
    }

    private var selected: ToolRecord? {
        model.toolListing?.tool(named: model.toolsSelected ?? "")
    }

    private func keepSelectionValid() {
        if selected == nil || selected?.isAgent == true {
            model.toolsSelected = model.toolListing?.others.first?.tool
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(summary).font(.headline)
            if model.toolsRefreshing {
                ProgressView().controlSize(.small)
                Text("looking for keys…").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", action: actions.reload).disabled(model.toolsRefreshing)
            Button("Wrap Another…") { actions.openSheet(.handWrap) }.disabled(model.toolsBusy != nil)
                .help("A tool jit's catalog does not know, which reads a token from an environment variable.")
            Button("Open in Terminal", action: actions.openInTerminal)
        }
    }

    private var summary: String {
        guard let listing = model.toolListing else {
            return "Tools"
        }
        // A denominator, so the count reads as "of the tools jit can wrap"
        // rather than an inventory of everything installed.
        let catalog = listing.tools.filter { $0.catalog && !$0.isAgent }.count
        let wrapped = listing.wrapped.filter { !$0.isAgent }.count
        let broken = listing.broken.filter { !$0.isAgent }.count
        var parts = ["\(listing.others.count) of jit's \(catalog) tools installed here"]
        parts.append("\(wrapped) wrapped")
        if broken > 0 {
            parts.append("\(broken) broken")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - List

    private func list(_ listing: ToolListing) -> some View {
        ScrollViewReader { proxy in
            // Tools only: the AI CLIs have their own window, where their
            // three facts get three lines each instead of one clause.
            List(selection: $model.toolsSelected) {
                ForEach(ordered(listing.others)) { row($0) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onChange(of: model.toolsSelected) { _, new in
                if let new {
                    proxy.scrollTo(new)
                }
            }
        }
    }

    /// Keys in the open first, then what jit already protects, then rows
    /// with nothing to do; catalog order within each.
    private func ordered(_ tools: [ToolRecord]) -> [ToolRecord] {
        func rank(_ tool: ToolRecord) -> Int {
            if tool.wrapped, !tool.isHealthy {
                return 0
            }
            if tool.keyState(scan: model.macScan).needsAction || expiredSessions(tool) > 0 {
                return 1
            }
            return tool.isProtected ? 2 : 3
        }
        return tools.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    private func row(_ tool: ToolRecord) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor(tool)).frame(width: 7, height: 7)
            Text(tool.tool).fontWeight(.semibold).frame(width: 110, alignment: .leading)
            Text(tool.shortDoc).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).help(tool.doc ?? "")
            Spacer()
            Text(stateText(tool)).foregroundStyle(.secondary).lineLimit(1).frame(width: 190, alignment: .trailing)
            rowButton(tool)
        }
        .padding(.vertical, 2)
        .tag(tool.tool)
        .id(tool.tool)
    }

    /// Green: wrapped and healthy, or native and protected. Red: wrapped
    /// but the shim or profile is broken. Amber: a key is in the open and
    /// one command moves it. Grey: nothing found, nothing to do.
    private func dotColor(_ tool: ToolRecord) -> Color {
        if expiredSessions(tool) > 0 {
            return Color(StatusMark.amber)
        }
        if tool.isProtected {
            return Color(StatusMark.green)
        }
        if tool.wrapped {
            return Color(StatusMark.red)
        }
        if tool.keyState(scan: model.macScan).needsAction {
            return Color(StatusMark.amber)
        }
        return Color.secondary.opacity(0.5)
    }

    /// The row answers "is there a key to protect" before "did jit wrap
    /// it": where the key sits, or that none was found. An agent row adds
    /// its cache verdict, the second fact of three (design §5).
    private func stateText(_ tool: ToolRecord) -> String {
        let key = keyText(tool)
        guard let label = tool.agentLabel else {
            return key
        }
        return key + " · " + cachesText(label)
    }

    /// Sessions this capture tool minted that have run out: the panel's
    /// "1 expired", so the row has to say the same.
    private func expiredSessions(_ tool: ToolRecord) -> Int {
        (model.cli?.sessions(mintedBy: tool.tool) ?? []).filter { !$0.live }.count
    }

    private func keyText(_ tool: ToolRecord) -> String {
        let expired = expiredSessions(tool)
        if expired > 0 {
            return "\(expired) expired session\(expired == 1 ? "" : "s")"
        }
        if tool.wrapped {
            return tool.isHealthy ? "wrapped" : tool.stateLabel
        }
        if tool.kind == "rungrant" || (tool.isGrant && tool.mountMigrated) {
            return "not wrapped"
        }
        switch tool.keyState(scan: model.macScan) {
        case .protected: return "protected"
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
            return (tool.isNative ? "credentials in " : "key in ") + Format.home(source)
        case .found: return "token in \(tool.tool)'s keychain"
        case .none: return tool.isNative ? "nothing found" : "no key found"
        case .unknown: return "not checked"
        }
    }

    private func cachesText(_ label: String) -> String {
        guard let scan = model.macScan else {
            return "not scanned yet"
        }
        let copies = scan.agentCopies(in: label)
        return copies == 0 ? "caches clean" : "\(copies) cached cop\(copies == 1 ? "y" : "ies")"
    }

    @ViewBuilder private func rowButton(_ tool: ToolRecord) -> some View {
        if model.toolsBusy == tool.tool {
            Text("Touch ID…").foregroundStyle(.secondary)
        } else if tool.isNative {
            // Only when the scan found the tool's credential file: migrate
            // on nothing answers "Nothing to migrate", and a button that
            // does that is noise.
            if tool.keyState(scan: model.macScan).needsAction {
                Button("Protect…") { actions.protect(tool.tool) }.controlSize(.small).disabled(model.toolsBusy != nil)
            }
        } else if tool.isGrant, !tool.mountMigrated {
            // The file is not in the vault yet: migrate it first (the
            // Protect the scan window offers), then the wrap has a mount
            // to grant.
            if case let .found(path) = tool.keyState(scan: model.macScan) {
                Button("Protect…") { actions.protectFile(path) }.controlSize(.small).disabled(model.toolsBusy != nil)
            }
        } else if !tool.wrapped {
            Button("Wrap…") { actions.openSheet(.wrap(tool: tool.tool)) }.controlSize(.small).disabled(model.toolsBusy != nil)
        } else if !tool.isHealthy {
            Button("Repair…") { actions.openSheet(.wrap(tool: tool.tool)) }.controlSize(.small).disabled(model.toolsBusy != nil)
        }
    }

    private var selectionBar: some View {
        ToolSelectionBar(model: model, actions: actions, tool: selected)
    }
}

struct ToolsActions {
    var reload: () -> Void = {}
    var openSheet: (ToolsSheet) -> Void = { _ in }
    var closeSheet: () -> Void = {}
    /// tool, and the key to store first when jit has nothing to discover
    var wrap: (String, String?) -> Void = { _, _ in }
    /// tool, variable, key: store the key at wrap-<tool>/VAR, then wrap add
    var handWrap: (String, String, String) -> Void = { _, _, _ in }
    var protect: (String) -> Void = { _ in }
    /// migrate one credential file, for a grant tool whose mount is not there yet
    var protectFile: (String) -> Void = { _ in }
    var unwrap: (String) -> Void = { _ in }
    var verify: (String) -> Void = { _ in }
    var mintInTerminal: (String) -> Void = { _ in }
    var cleanCaches: () -> Void = {}
    var scanNow: () -> Void = {}
    var openVault: () -> Void = {}
    var openSettings: () -> Void = {}
    var openInTerminal: () -> Void = {}
}
