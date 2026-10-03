// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The sheet the Tools window has open, if any.
enum ToolsSheet: Identifiable, Equatable {
    /// Wrap (or re-wrap) a catalog tool, with the key typed in when jit
    /// has nothing to discover.
    case wrap(tool: String)
    /// Wrap a tool outside the catalog: name, the variable it reads, the
    /// key. `jit wrap add`.
    case handWrap
    /// What an action did, as rows (`ChangeSheet`). There is no sheet of
    /// a command's printout: its words are under a failure or behind the
    /// disclosure.
    case changes(ChangeSheet)
    /// The Findings window's question before a scan: how far to look, for
    /// this scope (nil: the whole Mac).
    case scanDepth(scope: String?)

    var id: String {
        switch self {
        case let .wrap(tool): "wrap:" + tool
        case .handWrap: "handwrap"
        case let .changes(sheet): "changes:" + sheet.title
        case let .scanDepth(scope): "depth:" + (scope ?? "mac")
        }
    }
}

/// Wrap a catalog tool. Says what `jit wrap <tool>` will do in the
/// catalog's own words before anything runs, and offers the key field
/// when the vault holds nothing for it yet: the CLI would install the
/// shim and tell the user to `jit vault set` afterwards, which is the one
/// step a sheet with a SecureField can fold in.
struct WrapSheet: View {
    @ObservedObject var model: MenuModel
    let actions: ToolsActions
    let tool: ToolRecord

    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.five) {
            Text((tool.wrapped ? "Repair " : "Wrap ") + tool.tool + "?").font(Design.Text.windowHead)
            VStack(alignment: .leading, spacing: Design.Space.three) {
                ForEach(lines, id: \.self) { line in
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(Design.Text.row)
            if let inject = tool.injects.first, !inject.stored, !tool.keyState(scan: model.macScan).found {
                SheetField(inject.name) {
                    SecureField(fieldPrompt, text: $value).textFieldStyle(.roundedBorder)
                }
                Text(fieldNote).font(Design.Text.rowFact).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if Self.shimsMissingFromShell {
                Text("Terminal windows already open won't use it; open a new one.")
                    .font(Design.Text.rowFact).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.toolsMessage {
                Text(message)
                    .font(Design.Text.row)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Design.Space.five)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(StatusMark.red).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
            }
            HStack {
                Spacer()
                Button("Cancel", action: actions.closeSheet).keyboardShortcut(.cancelAction)
                Button(busy ? "Waiting for Touch ID…" : (tool.wrapped ? "Repair" : "Wrap")) {
                    actions.wrap(tool.tool, value.isEmpty ? nil : value)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || model.toolsBusy != nil)
            }
        }
        .padding(Design.Space.six)
        .frame(width: Design.Sheet.alert)
    }

    /// The shell a new terminal starts does not have jit's shims on its
    /// PATH yet: the first wrap adds the rc line, and only windows opened
    /// after it pick it up. Otherwise open windows already have it.
    static var shimsMissingFromShell: Bool {
        let shims = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jit/shims").path
        guard let path = LoginShell.path else {
            return true
        }
        return !path.split(separator: ":").contains(Substring(shims))
    }

    private var busy: Bool {
        model.toolsBusy == tool.tool
    }

    /// Whether `jit wrap` will find the key itself: the listing looked
    /// and found it, or the listing did not look and the catalog knows
    /// where to.
    private var discoverable: Bool {
        if let found = tool.keyFound {
            return found
        }
        return !tool.sources.isEmpty || tool.tokenCommand != nil
    }

    private var canSubmit: Bool {
        if let inject = tool.injects.first, !inject.stored, !discoverable {
            return !value.isEmpty
        }
        return true
    }

    /// Two short sentences at most: what changes for the tool, and where
    /// its key comes from; then the cost. The row already said what the
    /// tool is.
    private var lines: [String] {
        let name = tool.tool
        var lines: [String]
        switch tool.kind {
        case "capture":
            lines = [
                "Each \(name) login is kept in the vault instead of ~/.aws/credentials, and the AWS tools read it from there.",
                "A client secret in its config moves to the vault too."
            ]
        case "grant":
            lines = ["Each run of \(name) gets the \(tool.with ?? "") file after its own Touch ID. Everything else keeps getting decoys."]
        case "rungrant":
            lines = ["Each run of \(name) happens inside a jit grant. Nothing is stored."]
        case "store":
            lines = [Format.storeWrapLine(tool, family: model.toolListing?.family(of: name) ?? [name])]
        default:
            lines = ["\(name) gets its key from the vault, only while it runs."]
            if let key = tool.shellConfigKey(scan: model.macScan) {
                lines.append("The key moves out of \(Format.home(key.file)); your shell still gets it through jit.")
            } else {
                switch tool.keyState(scan: model.macScan) {
                case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
                    lines.append("The key moves out of \(Format.home(source)), which is backed up and emptied.")
                case .found:
                    lines.append("The key is copied from \(name)'s login, which stays as it is.")
                case .none, .unknown, .protected:
                    if discoverable {
                        lines.append("jit looks for the key in \(placesText).")
                    }
                }
            }
        }
        lines.append(needsField ? "Touch ID follows, once to store the key and once to wrap." : "Touch ID follows.")
        return lines
    }

    private var placesText: String {
        var places = tool.sources.map(Format.home)
        if let command = tool.tokenCommand {
            places.append(command)
        }
        return places.joined(separator: " or ")
    }

    private var needsField: Bool {
        if let inject = tool.injects.first, !inject.stored, !tool.keyState(scan: model.macScan).found {
            return !discoverable
        }
        return false
    }

    private var fieldPrompt: String {
        discoverable ? "optional: used if jit finds nothing" : "the key \(tool.tool) uses"
    }

    private var fieldNote: String {
        discoverable
            ? "Optional: leave empty to let jit find the key; fill in to store this value first."
            : "jit has nowhere to look for \(tool.tool)'s key, so paste it here."
    }
}

/// Wrap a tool the catalog does not know: its name (what you type in the
/// terminal), the environment variable it reads its token from, and the
/// token. The value goes to jit through a pipe, never an argument; the
/// wrap profile is the same shape a catalog wrap gets.
struct HandWrapSheet: View {
    @ObservedObject var model: MenuModel
    let actions: ToolsActions

    @State private var tool = ""
    @State private var name = ""
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wrap Another Tool").font(.headline)
                Text("For a CLI that reads a token from an environment variable. jit stores the token, "
                    + "puts a shim on PATH under the tool's name, and injects the variable into that process only.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SheetField("Tool") {
                TextField("acme-cli", text: $tool).textFieldStyle(.roundedBorder)
                    .help("The command name as you type it; the shim takes the same name.")
            }
            SheetField("Variable") {
                TextField("ACME_API_TOKEN", text: $name).textFieldStyle(.roundedBorder)
                    .help("The environment variable the tool reads.")
            }
            SheetField("Token") {
                SecureField("", text: $value).textFieldStyle(.roundedBorder)
                Text("Stored at wrap-\(tool.isEmpty ? "<tool>" : tool)/\(name.isEmpty ? "<VAR>" : name). Touch ID once.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let installed = installedNote {
                Text(installed).font(.system(size: 11)).foregroundStyle(Color(StatusMark.amber))
            }
            if let message = model.toolsMessage {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(StatusMark.red).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            HStack {
                Spacer()
                Button("Cancel", action: actions.closeSheet).keyboardShortcut(.cancelAction)
                Button(model.toolsBusy == nil ? "Wrap" : "Waiting for Touch ID…") {
                    actions.handWrap(tool.trimmingCharacters(in: .whitespaces), name.trimmingCharacters(in: .whitespaces), value)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || model.toolsBusy != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    /// A catalog tool has its own sheet with discovery; say so rather
    /// than wrap it blind.
    private var installedNote: String? {
        let trimmed = tool.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let record = model.toolListing?.tool(named: trimmed), record.catalog else {
            return nil
        }
        return "\(trimmed) is in jit's catalog: close this and use its own Wrap, which finds the key itself."
    }

    private var canSubmit: Bool {
        HandWrap.isValid(tool: tool.trimmingCharacters(in: .whitespaces), name: name.trimmingCharacters(in: .whitespaces))
            && !value.isEmpty && installedNote == nil
    }
}

/// What `jit wrap add` accepts: a tool name with no slash or space, and
/// an environment variable name.
enum HandWrap {
    static func isValid(tool: String, name: String) -> Bool {
        guard !tool.isEmpty, !tool.contains("/"), !tool.contains(" "), !tool.hasPrefix("-") else {
            return false
        }
        guard let first = name.first, first == "_" || first.isLetter else {
            return false
        }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }
}

/// What the Tools window has open over it: a wrap's question, or what an
/// action did, as rows.
struct ToolsSheetHost: View {
    @ObservedObject var model: MenuModel
    let actions: ToolsActions
    let sheet: ToolsSheet

    var body: some View {
        switch sheet {
        case let .wrap(tool):
            if let record = model.toolListing?.tool(named: tool) {
                WrapSheet(model: model, actions: actions, tool: record)
            }
        case .handWrap:
            HandWrapSheet(model: model, actions: actions)
        case let .changes(changes):
            ChangeSheetView(
                sheet: changes,
                reveal: actions.reveal,
                copyPath: actions.copyPath,
                undo: { actions.closeSheet(); actions.undoProtect(changes.undo) },
                close: actions.closeSheet,
                verify: { actions.closeSheet(); actions.verify($0) },
                protectAgain: { actions.closeSheet(); actions.protectAgain($0) }
            )
        case .scanDepth:
            // Findings' sheet; never opened here.
            EmptyView()
        }
    }
}
