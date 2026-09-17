// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

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
