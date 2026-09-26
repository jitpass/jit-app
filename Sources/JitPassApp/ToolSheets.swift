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
    /// What a command printed, verbatim: the CLI is the one that says what
    /// it found and moved.
    case result(title: String, text: String)
    /// What a Redact or a Protect changed, as rows (`ChangeSheet`).
    case changes(ChangeSheet)
    /// The Findings window's question before a scan: how far to look, for
    /// this scope (nil: the whole Mac).
    case scanDepth(scope: String?)

    var id: String {
        switch self {
        case let .wrap(tool): "wrap:" + tool
        case .handWrap: "handwrap"
        case let .result(title, _): "result:" + title
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
        VStack(alignment: .leading, spacing: 12) {
            Text((tool.wrapped ? "Repair " : "Wrap ") + tool.tool).font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(point).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if let inject = tool.injects.first, !inject.stored, !tool.keyState(scan: model.macScan).found {
                SheetField(inject.name) {
                    SecureField(fieldPrompt, text: $value).textFieldStyle(.roundedBorder)
                }
                Text(fieldNote).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Open shells keep the old PATH until you run the line below in them, or open a new one.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("export PATH=\"$HOME/.jit/shims:$PATH\"").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
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
                Button(busy ? "Waiting for Touch ID…" : (tool.wrapped ? "Repair" : "Wrap")) {
                    actions.wrap(tool.tool, value.isEmpty ? nil : value)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || model.toolsBusy != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
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

    /// Three lines, not a paragraph: where the key comes from, who gets
    /// it, what it costs. The row already said what the tool is.
    private var points: [String] {
        let target = tool.injects.first?.vaultPath ?? "wrap-\(tool.tool)/…"
        switch tool.kind {
        case "capture":
            return [
                "Every `\(tool.tool) get` login goes into the vault, not ~/.aws/credentials",
                "aws and the SDKs read it from there through credential_process",
                "A client secret in its config moves to the vault too · Touch ID once"
            ]
        case "grant":
            return [
                "Every run is granted the \(tool.with ?? "") mount under its own Touch ID",
                "The file on disk keeps serving decoys to everything else",
                "No token is moved"
            ]
        case "rungrant":
            return [
                "Every run happens inside a jit grant",
                "Migrated Secret manifests apply with real values; nothing else sees them",
                "No token, nothing to store"
            ]
        default:
            if let key = tool.shellConfigKey(scan: model.macScan) {
                return [
                    "Key: exported in \(Format.home(key.file)) · moves to \(key.vaultPath), the export line becomes jit's",
                    "\(tool.tool) gets it through the shim; your shell keeps it through jit export",
                    "Touch ID once"
                ]
            }
            var lines: [String] = switch tool.keyState(scan: model.macScan) {
            case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
                ["Key: found in \(Format.home(source)) · moves to \(target), file blanked (backed up)"]
            case let .found(source):
                ["Key: from \(tool.tool)'s login (`\(source)`) · copied to \(target), login untouched"]
            case .none, .unknown, .protected:
                [discoverable
                    ? "Key: jit looks in \(placesText) · stored at \(target)"
                    : "Key: the one you paste below · stored at \(target)"]
            }
            lines.append("Only \(tool.tool)'s own process gets it, one run at a time")
            lines.append("Touch ID once" + (needsField ? " to store it, once to wrap" : ""))
            return lines
        }
    }

    private var placesText: String {
        var places = tool.sources.map(Format.home)
        if let command = tool.tokenCommand {
            places.append("`\(command)`")
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

/// What a command printed, verbatim. The CLI is the one that says what it
/// found, moved and backed up; the sheet only frames it.
struct ResultSheet: View {
    let title: String
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 320)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack {
                Spacer()
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
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
